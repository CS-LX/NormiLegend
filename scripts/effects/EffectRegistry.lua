-- ============================================================================
-- effects/EffectRegistry.lua - 动态效果注册中心
-- 对修改关闭，对扩展开放：新增效果只需调用 Register()，无需改动此文件
-- ============================================================================

local M = {}

--- 效果注册表: id → { name, params_schema, apply(t, params) }
local registry = {}

--- 注册一个效果类型
---@param id string 效果唯一标识
---@param def table { name: string, params_schema: table[], apply: function }
function M.Register(id, def)
    registry[id] = def
end

--- 获取所有已注册效果（编辑器 UI 用）
---@return table<string, table>
function M.GetAll()
    return registry
end

--- 获取单个效果定义
---@param id string
---@return table|nil
function M.Get(id)
    return registry[id]
end

--- 获取效果 ID 列表（有序，编辑器下拉菜单用）
---@return string[]
function M.GetIds()
    local ids = {}
    for id, _ in pairs(registry) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    return ids
end

--- 对物件应用所有效果，返回渲染变换参数 + 可选渲染上下文
---@param effects table[]|nil 物件的 effects 列表
---@param t number 当前时间（秒）
---@return number dx X偏移(米)
---@return number dy Y偏移(米)
---@return number scale 缩放因子
---@return number angle 旋转角度(弧度)
---@return number alpha 透明度因子
---@return table|nil renderCtx 视觉类效果的渲染上下文（nil表示无特殊渲染）
function M.Apply(effects, t)
    local dx, dy, scale, angle, alpha = 0, 0, 1.0, 0, 1.0
    local renderCtx = nil
    if not effects then return dx, dy, scale, angle, alpha, renderCtx end
    for _, eff in ipairs(effects) do
        local def = registry[eff.id]
        if def and def.apply then
            local edx, edy, esc, eang, ealp, ectx = def.apply(t, eff.params or {})
            dx = dx + (edx or 0)
            dy = dy + (edy or 0)
            scale = scale * (esc or 1.0)
            angle = angle + (eang or 0)
            alpha = alpha * (ealp or 1.0)
            if ectx then renderCtx = ectx end
        end
    end
    return dx, dy, scale, angle, alpha, renderCtx
end

return M
