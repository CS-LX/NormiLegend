-------------------------------------------------------------------
-- Prefab.lua  —  预制体序列化 / 反序列化 / 文件管理
-------------------------------------------------------------------
local cjson = require("cjson")
local SN    = require("StrategyNode")

local M = {}

-- 预制体保存目录（相对路径，在 assets 目录下）
M.PREFAB_DIR = "prefabs"

-------------------------------------------------------------------
-- 内部工具
-------------------------------------------------------------------

--- 深拷贝 texLayers
local function copyTexLayers(layers)
    if not layers then return nil end
    local out = {}
    for _, l in ipairs(layers) do
        out[#out + 1] = {
            path      = l.path,
            name      = l.name,
            opacity   = l.opacity,
            scaleW    = l.scaleW,
            scaleH    = l.scaleH,
            rotation  = l.rotation,
            visible   = l.visible,
            lockAspect = l.lockAspect,
        }
    end
    return out
end

--- 深拷贝 effects
local function copyEffects(effects)
    if not effects then return nil end
    local out = {}
    for _, e in ipairs(effects) do
        local params = {}
        if e.params then
            for k, v in pairs(e.params) do params[k] = v end
        end
        out[#out + 1] = { id = e.id, params = params }
    end
    return out
end

--- 序列化单个对象为纯数据表（与 TitleMenu 的 serializeObject 对齐）
local function serializeObject(obj)
    local o = {
        type = obj.type,
        x    = obj.x,
        y    = obj.y,
        w    = obj.w,
        h    = obj.h,
        name = obj.name or "",
    }
    if obj.rotation and obj.rotation ~= 0 then o.rotation = obj.rotation end
    if obj.color then o.color = obj.color end

    -- texLayers
    if obj.texLayers and #obj.texLayers > 0 then
        o.texLayers = copyTexLayers(obj.texLayers)
    end

    -- effects
    if obj.effects and #obj.effects > 0 then
        o.effects = copyEffects(obj.effects)
    end

    -- trigger 专属
    if obj.type == "trigger" then
        o.triggerMethod     = obj.triggerMethod or "none"
        o.triggerMethodDesc = obj.triggerMethodDesc
        if obj.triggerStrategy and obj.triggerStrategy.rootId then
            o.triggerStrategy = SN.Serialize(obj.triggerStrategy)
        end
    end

    -- executor 专属
    if obj.type == "executor" then
        o.executorEffect     = obj.executorEffect or "none"
        o.executorEffectDesc = obj.executorEffectDesc
        o.hasCollision       = obj.hasCollision
        if obj.executorStrategy and obj.executorStrategy.rootId then
            o.executorStrategy = SN.Serialize(obj.executorStrategy)
        end
    end

    return o
end

-------------------------------------------------------------------
-- 公开 API
-------------------------------------------------------------------

--- 将选中的对象列表序列化为预制体数据
--- @param objects table       全局对象列表
--- @param selectedIndices table  选中对象的全局索引数组（1-based）
--- @return table prefabData   可直接 JSON 编码的预制体数据
function M.SerializeObjects(objects, selectedIndices)
    -- 构造 globalIndex → localIndex 映射
    local globalToLocal = {}
    for localIdx, globalIdx in ipairs(selectedIndices) do
        globalToLocal[globalIdx] = localIdx
    end

    -- 计算锚点（选中对象的几何中心）
    local sumX, sumY = 0, 0
    for _, gi in ipairs(selectedIndices) do
        local obj = objects[gi]
        sumX = sumX + obj.x
        sumY = sumY + obj.y
    end
    local anchorX = sumX / #selectedIndices
    local anchorY = sumY / #selectedIndices

    -- 序列化各对象，转为相对坐标
    local items = {}
    for localIdx, globalIdx in ipairs(selectedIndices) do
        local obj = objects[globalIdx]
        local item = serializeObject(obj)
        -- 转相对坐标
        item.dx = item.x - anchorX
        item.dy = item.y - anchorY
        item.x  = nil
        item.y  = nil
        -- localIndex 标记
        item.localIndex = localIdx

        -- mappings 重映射：只保留指向选中集内部的索引
        if obj.mappings and #obj.mappings > 0 then
            local remapped = {}
            for _, targetGlobal in ipairs(obj.mappings) do
                local targetLocal = globalToLocal[targetGlobal]
                if targetLocal then
                    remapped[#remapped + 1] = targetLocal
                end
            end
            item.mappings = remapped
        end

        items[#items + 1] = item
    end

    return {
        version = 1,
        anchorX = anchorX,
        anchorY = anchorY,
        items   = items,
    }
end

--- 将预制体数据实例化到关卡中
--- @param prefabData table    预制体数据（从 JSON 解码后）
--- @param placeX number       放置世界坐标 X
--- @param placeY number       放置世界坐标 Y
--- @param objects table       当前关卡的全局对象列表（将直接 insert）
--- @return table newIndices   新插入对象的全局索引数组
function M.InstantiateObjects(prefabData, placeX, placeY, objects)
    local items = prefabData.items
    local baseIndex = #objects  -- 新对象起始全局索引将是 baseIndex+1

    -- localIndex → newGlobalIndex 映射
    local localToGlobal = {}

    -- 第一遍：插入对象，分配新全局索引
    local newIndices = {}
    for _, item in ipairs(items) do
        local obj = {
            type     = item.type,
            x        = placeX + (item.dx or 0),
            y        = placeY + (item.dy or 0),
            w        = item.w,
            h        = item.h,
            name     = item.name or "",
            rotation = item.rotation,
            color    = item.color,
        }

        -- texLayers
        if item.texLayers and #item.texLayers > 0 then
            obj.texLayers = copyTexLayers(item.texLayers)
        end

        -- effects
        if item.effects and #item.effects > 0 then
            obj.effects = copyEffects(item.effects)
        end

        -- trigger
        if item.type == "trigger" then
            obj.triggerMethod     = item.triggerMethod
            obj.triggerMethodDesc = item.triggerMethodDesc
            obj.mappings          = {}  -- 先占位，第二遍重映射
            if item.triggerStrategy then
                obj.triggerStrategy = SN.Deserialize(item.triggerStrategy)
            end
        end

        -- executor
        if item.type == "executor" then
            obj.executorEffect     = item.executorEffect
            obj.executorEffectDesc = item.executorEffectDesc
            obj.hasCollision       = item.hasCollision
            obj.mappings           = {}
            if item.executorStrategy then
                obj.executorStrategy = SN.Deserialize(item.executorStrategy)
            end
        end

        table.insert(objects, obj)
        local newGlobalIdx = #objects
        newIndices[#newIndices + 1] = newGlobalIdx
        localToGlobal[item.localIndex] = newGlobalIdx
    end

    -- 第二遍：重映射 mappings（localIndex → 新全局索引）
    for i, item in ipairs(items) do
        if item.mappings and #item.mappings > 0 then
            local obj = objects[newIndices[i]]
            obj.mappings = {}
            for _, targetLocal in ipairs(item.mappings) do
                local targetGlobal = localToGlobal[targetLocal]
                if targetGlobal then
                    obj.mappings[#obj.mappings + 1] = targetGlobal
                end
            end
        end
    end

    return newIndices
end

--- 保存预制体到文件
--- @param name string         预制体名称（用作文件名）
--- @param objects table       全局对象列表
--- @param selectedIndices table  选中对象的全局索引数组
--- @return boolean success
--- @return string? error
function M.SavePrefab(name, objects, selectedIndices)
    if not name or name == "" then
        return false, "预制体名称不能为空"
    end
    if not selectedIndices or #selectedIndices == 0 then
        return false, "没有选中任何对象"
    end

    local prefabData = M.SerializeObjects(objects, selectedIndices)
    prefabData.name = name
    prefabData.objectCount = #selectedIndices

    local jsonStr = cjson.encode(prefabData)

    -- 确保目录存在
    fileSystem:CreateDir(M.PREFAB_DIR)

    local filePath = M.PREFAB_DIR .. "/" .. name .. ".prefab.json"
    local file = File(filePath, FILE_WRITE)
    if not file or not file:IsOpen() then
        return false, "无法写入文件: " .. filePath
    end
    file:WriteString(jsonStr)
    file:Close()

    print("[Prefab] 已保存预制体: " .. filePath .. " (" .. #selectedIndices .. " 个对象)")
    return true
end

--- 加载预制体文件
--- @param filePath string   文件路径（相对）
--- @return table? prefabData
--- @return string? error
function M.LoadPrefab(filePath)
    local file = File(filePath, FILE_READ)
    if not file or not file:IsOpen() then
        return nil, "无法读取文件: " .. filePath
    end
    local jsonStr = file:ReadString()
    file:Close()

    if not jsonStr or jsonStr == "" then
        return nil, "文件为空: " .. filePath
    end

    local ok, data = pcall(cjson.decode, jsonStr)
    if not ok then
        return nil, "JSON 解析失败: " .. tostring(data)
    end

    return data
end

--- 列出所有可用预制体
--- @return table[] list  每项包含 {name, filePath, objectCount}
function M.ListPrefabs()
    local list = {}
    local dir = M.PREFAB_DIR

    -- 扫描目录中的 .prefab.json 文件
    if not fileSystem:DirExists(dir) then
        return list
    end

    local files = fileSystem:ScanDir(dir, "*.prefab.json", SCAN_FILES, false)
    if files then
        for _, fileName in ipairs(files) do
            local filePath = dir .. "/" .. fileName
            -- 尝试读取元信息（名称、数量）
            local data = M.LoadPrefab(filePath)
            if data then
                list[#list + 1] = {
                    name        = data.name or fileName:gsub("%.prefab%.json$", ""),
                    filePath    = filePath,
                    objectCount = data.objectCount or (data.items and #data.items or 0),
                }
            end
        end
    end

    return list
end

--- 删除预制体
--- @param filePath string
--- @return boolean
function M.DeletePrefab(filePath)
    if fileSystem:FileExists(filePath) then
        fileSystem:Delete(filePath)
        print("[Prefab] 已删除: " .. filePath)
        return true
    end
    return false
end

return M
