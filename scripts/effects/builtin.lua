-- ============================================================================
-- effects/builtin.lua - 内置效果集
-- 扩展方式：在此追加 Register() 调用，或新建独立文件
-- ============================================================================

local Registry = require("effects.EffectRegistry")

-- ═══════════ 浮动（上下悬浮）═══════════
Registry.Register("float", {
    name = "浮动",
    params_schema = {
        { key = "amp",   label = "振幅(米)", default = 0.3,  min = 0.05, max = 2.0 },
        { key = "speed", label = "速度",     default = 2.0,  min = 0.1,  max = 10.0 },
    },
    apply = function(t, p)
        local dy = math.sin(t * (p.speed or 2.0)) * (p.amp or 0.3)
        return 0, dy, nil, nil, nil
    end,
})

-- ═══════════ 脉冲缩放 ═══════════
Registry.Register("pulse", {
    name = "脉冲",
    params_schema = {
        { key = "min",   label = "最小缩放", default = 0.9,  min = 0.1, max = 1.0 },
        { key = "max",   label = "最大缩放", default = 1.1,  min = 1.0, max = 3.0 },
        { key = "speed", label = "速度",     default = 3.0,  min = 0.1, max = 10.0 },
    },
    apply = function(t, p)
        local pMin = p.min or 0.9
        local pMax = p.max or 1.1
        local mid = (pMin + pMax) / 2
        local range = (pMax - pMin) / 2
        local scale = mid + math.sin(t * (p.speed or 3.0)) * range
        return nil, nil, scale, nil, nil
    end,
})

-- ═══════════ 旋转 ═══════════
Registry.Register("rotate", {
    name = "旋转",
    params_schema = {
        { key = "speed", label = "角速度(度/秒)", default = 45, min = -720, max = 720 },
    },
    apply = function(t, p)
        local angleDeg = t * (p.speed or 45)
        local angleRad = math.rad(angleDeg % 360)
        return nil, nil, nil, angleRad, nil
    end,
})

-- ═══════════ 闪烁（透明度变化）═══════════
Registry.Register("blink", {
    name = "闪烁",
    params_schema = {
        { key = "min",   label = "最低透明度", default = 0.3, min = 0, max = 1 },
        { key = "speed", label = "速度",      default = 4.0, min = 0.1, max = 20 },
    },
    apply = function(t, p)
        local pMin = p.min or 0.3
        local mid = (1 + pMin) / 2
        local range = (1 - pMin) / 2
        local alpha = mid + range * math.sin(t * (p.speed or 4.0))
        return nil, nil, nil, nil, alpha
    end,
})

-- ═══════════ 摇晃（水平抖动）═══════════
Registry.Register("shake", {
    name = "摇晃",
    params_schema = {
        { key = "amp",   label = "振幅(米)", default = 0.1, min = 0.01, max = 1.0 },
        { key = "speed", label = "频率",    default = 8.0, min = 1,    max = 30 },
    },
    apply = function(t, p)
        local dx = math.sin(t * (p.speed or 8.0)) * (p.amp or 0.1)
        return dx, 0, nil, nil, nil
    end,
})

-- ═══════════ 弹跳（模拟弹性上下）═══════════
Registry.Register("bounce", {
    name = "弹跳",
    params_schema = {
        { key = "height", label = "高度(米)", default = 0.5, min = 0.1, max = 3.0 },
        { key = "speed",  label = "速度",    default = 3.0, min = 0.5, max = 10.0 },
    },
    apply = function(t, p)
        local phase = (t * (p.speed or 3.0)) % (math.pi * 2)
        local dy = math.abs(math.sin(phase)) * (p.height or 0.5)
        return nil, dy, nil, nil, nil
    end,
})

-- ═══════════ 序列帧（Sprite Sheet 动画）═══════════
Registry.Register("spritesheet", {
    name = "序列帧",
    params_schema = {
        { key = "path", label = "序列帧图片", default = "", type = "texture" },
        { key = "cols", label = "列数", default = 4, min = 1, max = 32 },
        { key = "rows", label = "行数", default = 1, min = 1, max = 32 },
        { key = "fps",  label = "帧率", default = 12, min = 1, max = 60 },
        { key = "loop", label = "循环", default = 1, min = 0, max = 1, type = "bool" },
    },
    apply = function(t, p)
        local cols = math.max(1, p.cols or 4)
        local rows = math.max(1, p.rows or 1)
        local fps = math.max(1, p.fps or 12)
        local totalFrames = cols * rows
        local frameIndex
        if (p.loop or 1) == 1 then
            frameIndex = math.floor(t * fps) % totalFrames
        else
            frameIndex = math.min(math.floor(t * fps), totalFrames - 1)
        end
        local ctx = {
            type = "spritesheet",
            path = p.path or "",
            frameIndex = frameIndex,
            cols = cols,
            rows = rows,
        }
        return nil, nil, nil, nil, nil, ctx
    end,
})
