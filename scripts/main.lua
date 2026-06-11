-- ============================================================================
-- 冰霜法师 - 平台跳跃游戏 (入口编排文件)
-- 基于 Box2D 物理 + NanoVG 渲染 + 序列帧动画
-- ============================================================================

require "LuaScripts/Utilities/Sample"
require "urhox-libs.UI.GameHUD"
local UI = require("urhox-libs/UI")
local Enemy = require("Enemy")
local BatEnemy = require("BatEnemy")
local CastleEnemies = require("CastleEnemies")
local GMConsole = require("GMConsole")
local WorldMap = require("WorldMap")
local LevelConfig = require("LevelConfig")
local SpriteEditor = require("SpriteEditor")
local Video = require("urhox-libs/Video")

-- 模块加载
local C = require("GameConfig")
local S = require("GameState")
local Renderer = require("Renderer")
local GameUI = require("GameUI")
local Level = require("Level")
local Player = require("Player")
local Combat = require("Combat")
local Animation = require("Animation")
local TitleMenu = require("TitleMenu")
local NodeCanvas = require("NodeCanvas")

-- ============================================================================
-- 主函数
-- ============================================================================
function Start()
    SampleStart()

    -- 创建 NanoVG 上下文
    S.nvg = nvgCreate(1)
    if S.nvg == nil then
        print("ERROR: 无法创建NanoVG上下文")
        return
    end

    -- 创建字体（香萃等粗宋）
    nvgCreateFont(S.nvg, "sans", "Fonts/XiangcuiDengcusong.ttf")

    -- 创建场景 → 世界 → 玩家
    Level.CreateScene()
    Level.CreateWorld()
    Level.CreatePlayer()

    -- 加载序列帧纹理
    Level.LoadSpriteSheets()

    -- 创建虚拟控制（HUD按钮）
    Player.CreateGameHUD()

    -- 初始化UI系统
    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/XiangcuiDengcusong.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 初始化自定义鼠标指针
    require("Cursor").Init()

    -- 创建UI面板
    GameUI.CreateSkillPanelUI()
    GameUI.CreateInventoryPanelUI()

    -- 初始化序列帧编辑器
    SpriteEditor.Init({
        getAnimCropConfig = function(charIdx)
            if charIdx == 2 then return S.animCropConfig2 end
            return S.animCropConfig1
        end,
        getAnimImages = function(charIdx)
            if charIdx == 2 then
                return { S.img2Idle, S.img2Run, S.img2Jump, S.img2Attack, S.img2Block, S.img2Burst, S.img2Heal, S.img2Crouch, S.img2CrouchWalk, S.img2Hit }
            else
                return { S.imgIdle, S.imgRun, S.imgJump, S.imgAttack, S.imgBlock, S.imgCharge, S.imgHeal, S.imgCrouch, S.imgCrouchWalk, S.imgHit }
            end
        end,
        getNvg = function() return S.nvg end,
        getImgSize = function() return S.imgWidth, S.imgHeight end,
        getCurrentChar = function() return S.currentCharacter end,
        getEnemyImages = function(typeKey)
            if typeKey == "bat" then
                return BatEnemy.GetImages()
            elseif typeKey == "stixia" then
                return Enemy.GetImages()
            else
                return CastleEnemies.GetImages(typeKey)
            end
        end,
        getEnemyImgSize = function(typeKey)
            if typeKey == "bat" then
                return BatEnemy.GetImageSize()
            elseif typeKey == "stixia" then
                return Enemy.GetImageSize()
            else
                return CastleEnemies.GetImageSize(typeKey)
            end
        end,
        enemyGridOverrides = {
            stixia = { cols = 2, rows = 2, frames = 4 },
        },
        spriteCols = C.SPRITE_COLS,
        spriteRows = C.SPRITE_ROWS,
        spriteFrames = C.SPRITE_FRAMES,
        playerRadius = C.PLAYER_RADIUS,
        pixelsPerUnit = C.PIXELS_PER_UNIT,
        screenWidth = C.SCREEN_WIDTH,
    })

    -- 右上角返回按钮（与背包/技能按钮一致样式）
    S.backButton = UI.Button {
        text = "返回", fontSize = 12,
        width = 56, height = 34,
        position = "absolute",
        top = 10, right = 10,
        backgroundColor = "rgba(0,0,0,0.6)",
        color = "#ffffff",
        borderRadius = 8,
        borderWidth = 1,
        borderColor = "rgba(255,255,255,0.3)",
        onClick = function()
            if not WorldMap.IsOnMap() and not WorldMap.IsEscPopup() then
                WorldMap.ShowEscPopup()
                GameUI.ShowEscPopupUI()
            end
        end,
    }

    -- 顶部功能按钮栏
    S.topButtonBar = UI.Panel {
        position = "absolute",
        top = 10, right = 74,
        flexDirection = "row",
        gap = 8,
        pointerEvents = "box-none",
        children = {
            UI.Button {
                text = "背包", fontSize = 12, width = 56, height = 34,
                backgroundColor = "rgba(0,0,0,0.6)", color = "#ffffff",
                borderRadius = 8, borderWidth = 1, borderColor = "rgba(255,255,255,0.3)",
                onClick = function() GameUI.ToggleInventoryPanel() end,
            },
            UI.Button {
                text = "技能", fontSize = 12, width = 56, height = 34,
                backgroundColor = "rgba(0,0,0,0.6)", color = "#ffffff",
                borderRadius = 8, borderWidth = 1, borderColor = "rgba(255,255,255,0.3)",
                onClick = function() GameUI.ToggleSkillPanel() end,
            },
            UI.Button {
                text = "控制台", fontSize = 11, width = 56, height = 34,
                backgroundColor = "rgba(0,0,0,0.6)", color = "#ffffff",
                borderRadius = 8, borderWidth = 1, borderColor = "rgba(255,255,255,0.3)",
                onClick = function() GMConsole.Toggle() end,
            },
            UI.Button {
                text = "序列帧", fontSize = 11, width = 56, height = 34,
                backgroundColor = "rgba(0,0,0,0.6)", color = "#ffffff",
                borderRadius = 8, borderWidth = 1, borderColor = "rgba(255,255,255,0.3)",
                onClick = function()
                    SpriteEditor.Toggle()
                end,
            },
            UI.Button {
                text = "地形", fontSize = 11, width = 56, height = 34,
                backgroundColor = "rgba(0,60,120,0.7)", color = "#88ccff",
                borderRadius = 8, borderWidth = 1, borderColor = "rgba(100,180,255,0.5)",
                onClick = function()
                    -- 使用最近游玩/编辑的关卡，默认1-1
                    local editorState = require("editor.EditorState").state
                    local ch = editorState.chapterIdx or 1
                    local lv = editorState.levelIdx or 1
                    TitleMenu.OpenEditorFromGame(ch, lv)
                end,
            },
        }
    }

    -- ESC离开确认弹窗
    S.escPopupUI = UI.Panel {
        id = "escPopupRoot",
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = { 0, 0, 0, 150 },
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = 300,
                backgroundColor = { 30, 30, 50, 240 },
                borderRadius = 12,
                borderWidth = 2,
                borderColor = { 180, 160, 120, 200 },
                padding = 20,
                alignItems = "center",
                children = {
                    UI.Label { text = "是否离开当前区域？", fontSize = 18, fontColor = { 255, 240, 200, 255 }, marginBottom = 8 },
                    UI.Label { id = "escAreaName", text = "", fontSize = 14, fontColor = { 180, 180, 200, 200 }, marginBottom = 20 },
                    UI.Panel {
                        flexDirection = "row",
                        gap = 24,
                        children = {
                            UI.Button {
                                text = "是，离开", fontSize = 15, width = 110, height = 40,
                                backgroundColor = { 60, 160, 80, 220 }, color = "#ffffff",
                                borderRadius = 8, borderWidth = 1.5, borderColor = { 100, 220, 120, 200 },
                                onClick = function()
                                    S.escPopupUI:Hide()
                                    WorldMap.CloseEscPopup()
                                    WorldMap.LeaveToMap()
                                    Enemy.Clear()
                                    BatEnemy.Clear()
                                    CastleEnemies.Clear()
                                end,
                            },
                            UI.Button {
                                text = "否，继续", fontSize = 15, width = 110, height = 40,
                                backgroundColor = { 120, 60, 60, 220 }, color = "#ffffff",
                                borderRadius = 8, borderWidth = 1.5, borderColor = { 200, 100, 100, 200 },
                                onClick = function()
                                    S.escPopupUI:Hide()
                                    WorldMap.CloseEscPopup()
                                end,
                            },
                        }
                    },
                }
            }
        }
    }
    S.escPopupUI:Hide()

    -- 关卡选择页面"返回标题"按钮
    S.mapBackButton = UI.Button {
        text = "← 返回", fontSize = 14,
        width = 72, height = 34,
        position = "absolute",
        top = 10, left = 10,
        backgroundColor = "rgba(0,0,0,0.6)",
        color = "#ffffff",
        borderRadius = 8,
        borderWidth = 1,
        borderColor = "rgba(255,255,255,0.3)",
        onClick = function()
            TitleMenu.ShowTransition(function() TitleMenu.ShowMainMenu() end)
        end,
    }

    -- 角色切换面板
    S.charSwitchPanel = UI.Panel {
        id = "charSwitchPanel",
        position = "absolute",
        right = 12, top = 80,
        pointerEvents = "box-none",
        alignItems = "center",
        gap = 10,
        children = {}
    }
    Player.RefreshCharSwitchPanel()

    -- 建立共享根节点
    local uiRoot = UI.Panel {
        width = "100%", height = "100%",
        pointerEvents = "box-none",
        children = { S.backButton, S.topButtonBar, S.mapBackButton, S.skillButtonPanel, S.charSwitchPanel, S.skillPanelUI, S.inventoryPanelUI, S.escPopupUI, SpriteEditor.GetPanel() }
    }
    UI.SetRoot(uiRoot)

    -- 订阅事件
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("PostUpdate", "HandlePostUpdate")
    SubscribeToEvent(S.nvg, "NanoVGRender", "HandleRender")
    SubscribeToEvent("PhysicsBeginContact2D", "HandlePhysicsBeginContact")
    SubscribeToEvent("PhysicsEndContact2D", "HandlePhysicsEndContact")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")

    -- 初始化敌人系统
    Enemy.Init(S.nvg)
    BatEnemy.Init(S.nvg)
    CastleEnemies.Init(S.nvg)

    -- 注册敌人到 Targetable 索敌系统
    Combat.RegisterEnemyProviders()

    -- 初始化大地图系统
    WorldMap.Init(S.nvg)

    -- 初始化GM控制台
    GMConsole.Init(S.nvg, {
        refillHP = function() S.playerHP = S.playerMaxHP; S.charStats[S.currentCharacter].hp = S.playerHP end,
        refillMP = function() S.playerMP = S.playerMaxMP; S.charStats[S.currentCharacter].mp = S.playerMP end,
        c1_maxHP_get = function() return S.charStats[1].maxHP end,
        c1_maxHP_set = function(v) S.charStats[1].maxHP = v; S.charStats[1].hp = math.min(S.charStats[1].hp, v); if S.currentCharacter == 1 then S.playerMaxHP = v; S.playerHP = math.min(S.playerHP, v) end end,
        c1_maxMP_get = function() return S.charStats[1].maxMP end,
        c1_maxMP_set = function(v) S.charStats[1].maxMP = v; S.charStats[1].mp = math.min(S.charStats[1].mp, v); if S.currentCharacter == 1 then S.playerMaxMP = v; S.playerMP = math.min(S.playerMP, v) end end,
        c1_projDmg_get = function() return C.PROJECTILE_DAMAGE end,
        c1_projDmg_set = function(v) C.PROJECTILE_DAMAGE = v end,
        c1_projSpeed_get = function() return C.PROJECTILE_SPEED end,
        c1_projSpeed_set = function(v) C.PROJECTILE_SPEED = v end,
        c1_projLife_get = function() return C.PROJECTILE_LIFETIME end,
        c1_projLife_set = function(v) C.PROJECTILE_LIFETIME = v end,
        c1_chargeDmg_get = function() return C.CHARGE_DAMAGE end,
        c1_chargeDmg_set = function(v) C.CHARGE_DAMAGE = v end,
        c1_chargeMP_get = function() return C.CHARGE_MP_COST end,
        c1_chargeMP_set = function(v) C.CHARGE_MP_COST = v end,
        c1_freezeDur_get = function() return C.CHARGE_FREEZE_DURATION end,
        c1_freezeDur_set = function(v) C.CHARGE_FREEZE_DURATION = v end,
        c1_healHP_get = function() return C.HEAL_HP_RESTORE end,
        c1_healHP_set = function(v) C.HEAL_HP_RESTORE = v end,
        c1_healMP_get = function() return C.HEAL_MP_COST end,
        c1_healMP_set = function(v) C.HEAL_MP_COST = v end,
        c1_healCD_get = function() return C.HEAL_COOLDOWN end,
        c1_healCD_set = function(v) C.HEAL_COOLDOWN = v end,
        c1_blockMP_get = function() return C.BLOCK_MP_PER_SEC end,
        c1_blockMP_set = function(v) C.BLOCK_MP_PER_SEC = v end,
        c2_maxHP_get = function() return S.charStats[2].maxHP end,
        c2_maxHP_set = function(v) S.charStats[2].maxHP = v; S.charStats[2].hp = math.min(S.charStats[2].hp, v); if S.currentCharacter == 2 then S.playerMaxHP = v; S.playerHP = math.min(S.playerHP, v) end end,
        c2_maxMP_get = function() return S.charStats[2].maxMP end,
        c2_maxMP_set = function(v) S.charStats[2].maxMP = v; S.charStats[2].mp = math.min(S.charStats[2].mp, v); if S.currentCharacter == 2 then S.playerMaxMP = v; S.playerMP = math.min(S.playerMP, v) end end,
        c2_meleeDmg_get = function() return C.CHAR2_MELEE_DAMAGE end,
        c2_meleeDmg_set = function(v) C.CHAR2_MELEE_DAMAGE = v end,
        c2_meleeRange_get = function() return C.CHAR2_MELEE_RANGE end,
        c2_meleeRange_set = function(v) C.CHAR2_MELEE_RANGE = v end,
        c2_dashDmg_get = function() return C.CHAR2_DASH_DAMAGE end,
        c2_dashDmg_set = function(v) C.CHAR2_DASH_DAMAGE = v end,
        c2_dashMP_get = function() return C.CHARGE_MP_COST end,
        c2_dashMP_set = function(v) C.CHARGE_MP_COST = v end,
        c2_dashSpeed_get = function() return C.CHAR2_DASH_SPEED end,
        c2_dashSpeed_set = function(v) C.CHAR2_DASH_SPEED = v end,
        c2_bleedDur_get = function() return C.CHAR2_BLEED_DURATION end,
        c2_bleedDur_set = function(v) C.CHAR2_BLEED_DURATION = v end,
        c2_bleedDPS_get = function() return C.CHAR2_BLEED_DPS end,
        c2_bleedDPS_set = function(v) C.CHAR2_BLEED_DPS = v end,
        c2_healHP_get = function() return 10 + (S.skillList2[3].level - 1) * 5 end,
        c2_healHP_set = function(v) end,
        c2_healMP_get = function() return C.HEAL_MP_COST end,
        c2_healMP_set = function(v) C.HEAL_MP_COST = v end,
        c2_healCD_get = function() return C.HEAL_COOLDOWN end,
        c2_healCD_set = function(v) C.HEAL_COOLDOWN = v end,
        c2_lifestealDur_get = function() return C.LIFESTEAL_DURATION end,
        c2_lifestealDur_set = function(v) C.LIFESTEAL_DURATION = v end,
        c2_lifestealPct_get = function() return C.LIFESTEAL_RATIO * 100 end,
        c2_lifestealPct_set = function(v) C.LIFESTEAL_RATIO = v / 100 end,
        c2_blockMP_get = function() return C.BLOCK_MP_PER_SEC end,
        c2_blockMP_set = function(v) C.BLOCK_MP_PER_SEC = v end,
        r_pixelsPerUnit_get = function() return C.PIXELS_PER_UNIT end,
        r_pixelsPerUnit_set = function(v) C.PIXELS_PER_UNIT = v end,
        r_screenW_get = function() return C.SCREEN_WIDTH end,
        r_screenW_set = function(v) C.SCREEN_WIDTH = v end,
        r_screenH_get = function() return C.SCREEN_HEIGHT end,
        r_screenH_set = function(v) C.SCREEN_HEIGHT = v end,
        getAnimCropConfig1 = function() return S.animCropConfig1 end,
        getAnimCropConfig2 = function() return S.animCropConfig2 end,
    })

    -- 创建GM控制台UI面板并挂载
    local gmPanel, gmExportPanel = GMConsole.CreateUI()
    if gmPanel then uiRoot:AddChild(gmPanel) end
    if gmExportPanel then uiRoot:AddChild(gmExportPanel) end

    -- 显示标题页面
    TitleMenu.ShowTitleScreen()

    print("=== 冰霜法师 - 平台跳跃游戏 ===")
    print("方向键/WASD移动, 空格/K跳跃, J/鼠标左键施法, 鼠标右键/L格挡")
    print("数字键0 打开GM控制台")
end

function Stop()
    GameHUD.Shutdown()
    UI.Shutdown()
    if S.nvg ~= nil then
        nvgDelete(S.nvg)
    end
end

-- ============================================================================
-- 触屏事件（用于大地图选关）
-- ============================================================================
function HandleTouchBegin(eventType, eventData)
    if S.showTitleScreen or S.showMainMenu then return end
    local x = eventData["X"]:GetInt()
    local y = eventData["Y"]:GetInt()
    S.mapTouchPressed = true
    S.mapTouchX = x
    S.mapTouchY = y
end

-- ============================================================================
-- 更新逻辑
-- ============================================================================
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 过场计时器
    TitleMenu.UpdateTransition(dt)

    -- 主菜单 Live2D 动画
    TitleMenu.UpdateMainMenuAnimation(dt)

    -- 章节选择动画更新
    TitleMenu.UpdateChapterSelect(dt)

    -- 关卡编辑器拖拽更新
    TitleMenu.UpdateLevelEditor(dt)

    -- 预览模式更新（角色移动/相机/ESC退出）
    TitleMenu.UpdatePreview(dt)

    -- 主菜单ESC处理：关闭关卡编辑器 / 关卡选择 / 章节选择 / 功能面板 / 返回标题
    -- 注意：预览模式的ESC已在UpdatePreview内部消耗，不会走到这里
    -- NodeCanvas 刚关闭 或 预览刚退出 时跳过本帧ESC，防止连锁退出到关卡选择
    if S.showMainMenu and not NodeCanvas.JustClosed() and not TitleMenu.JustStoppedPreview() and input:GetKeyPress(KEY_ESCAPE) then
        if TitleMenu.IsLevelEditorOpen() then
            TitleMenu.ExitLevelEditor()
        elseif TitleMenu.IsLevelSelectOpen() then
            TitleMenu.CloseLevelSelect()
        elseif TitleMenu.IsChapterSelectOpen() then
            TitleMenu.CloseChapterSelect()
        elseif TitleMenu.IsMenuPanelOpen() then
            TitleMenu.CloseMenuPanel()
        else
            -- 返回标题页
            S.showMainMenu = false
            S.mainMenuUIRoot = nil
            TitleMenu.ShowTransition(function() TitleMenu.ShowTitleScreen() end)
        end
    end

    -- 标题页面/主菜单/过场时跳过所有游戏逻辑
    if S.showTitleScreen or S.showMainMenu or TitleMenu.IsTransitionActive() then return end

    -- ========== UI 可见性控制 ==========
    local inLevel = not WorldMap.IsOnMap()
    local showHud = inLevel and not S.hudHidden
    if S.backButton then S.backButton:SetVisible(showHud) end
    if S.topButtonBar then S.topButtonBar:SetVisible(showHud) end
    if S.skillButtonPanel then S.skillButtonPanel:SetVisible(showHud) end
    if S.charSwitchPanel then S.charSwitchPanel:SetVisible(showHud) end
    if S.mapBackButton then S.mapBackButton:SetVisible(WorldMap.IsOnMap()) end

    -- ========== 大地图状态处理 ==========
    if WorldMap.IsOnMap() then
        -- ESC键返回（来自章节选择则回到章节选择，否则回主菜单）
        if input:GetKeyPress(KEY_ESCAPE) then
            if S.enteredGameFromChapterSelect then
                TitleMenu.ReturnToChapterSelect()
            else
                TitleMenu.ShowTransition(function() TitleMenu.ShowMainMenu() end)
            end
            return
        end

        -- 处理鼠标/触屏点击区域（适配 16:9 letterbox）
        local lbOx, lbOy, lbW, lbH = Renderer.CalcLetterbox(graphics:GetWidth(), graphics:GetHeight())
        local mouseX = input.mousePosition.x - lbOx
        local mouseY = input.mousePosition.y - lbOy
        local clicked = input:GetMouseButtonPress(MOUSEB_LEFT)

        -- 触屏支持：用TouchBegin事件标记检测新触摸
        if not clicked and S.mapTouchPressed then
            mouseX = S.mapTouchX - lbOx
            mouseY = S.mapTouchY - lbOy
            clicked = true
        end
        S.mapTouchPressed = false

        local selectedId = WorldMap.HandleMapInput(mouseX, mouseY, lbW, lbH, clicked)
        if selectedId then
            Level.LoadArea(selectedId)
        end
        return  -- 大地图状态不更新游戏逻辑
    end

    -- ========== ESC弹窗状态处理 ==========
    if WorldMap.IsEscPopup() then
        if input:GetKeyPress(KEY_ESCAPE) then
            if S.escPopupUI then S.escPopupUI:Hide() end
            WorldMap.CloseEscPopup()
        end
        return
    end

    -- ========== 正常关卡游戏逻辑 ==========

    -- ESC键处理：有面板打开时关闭面板，无面板时弹退出确认
    if input:GetKeyPress(KEY_ESCAPE) then
        if SpriteEditor.IsVisible() then
            SpriteEditor.Hide()
        elseif GMConsole.IsOpen() then
            GMConsole.Toggle()
        elseif S.showSkillPanel then
            GameUI.ToggleSkillPanel()
        elseif S.showInventory then
            GameUI.ToggleInventoryPanel()
        else
            WorldMap.ShowEscPopup()
            GameUI.ShowEscPopupUI()
        end
        return
    end

    -- 序列帧编辑器输入拦截（编辑器打开时阻塞游戏输入）
    if SpriteEditor.HandleInput() then return end
    -- GM控制台输入处理（不阻塞游戏，前台操作继续）
    GMConsole.HandleInput()

    -- 玩家输入与移动
    local desiredVelX = Player.Update(dt)

    -- 战斗系统更新
    Combat.ProcessPendingProjectile(dt)
    Combat.ProcessPendingMelee(dt)
    Combat.UpdateDash(dt)
    Combat.UpdateProjectiles(dt)
    Combat.UpdateIceCrystals(dt)
    Combat.CheckProjectileHits()

    -- 敌人AI更新
    if S.playerNode then
        local pPos = S.playerNode.position2D
        local camX = S.cameraNode and S.cameraNode.position.x or pPos.x
        local camY = S.cameraNode and S.cameraNode.position.y or pPos.y
        Enemy.Update(dt, pPos.x, pPos.y, S.playerHP)
        BatEnemy.Update(dt, pPos.x, pPos.y, camX, camY, C.SCREEN_WIDTH, C.SCREEN_HEIGHT, C.PIXELS_PER_UNIT)
        CastleEnemies.Update(dt, pPos.x, pPos.y, camX, camY, C.SCREEN_WIDTH, C.SCREEN_HEIGHT, C.PIXELS_PER_UNIT)

        -- 敌人攻击命中判定 & 玩家受伤处理
        local normalDmg, skillDmg = Enemy.CheckAttackHits(pPos.x, pPos.y)
        local batDmg = BatEnemy.CheckAttackHits(pPos.x, pPos.y)
        local castleDmg = CastleEnemies.CheckAttackHits(pPos.x, pPos.y)
        Combat.ProcessDamage(normalDmg, skillDmg, batDmg, castleDmg)
    end

    -- 动画状态机更新
    Animation.Update(dt, desiredVelX)
end

-- ============================================================================
-- 相机跟随
-- ============================================================================
function HandlePostUpdate(eventType, eventData)
    if S.showTitleScreen or S.showMainMenu then return end
    Player.UpdateCamera(eventData["TimeStep"]:GetFloat())
end

-- ============================================================================
-- 物理碰撞
-- ============================================================================
function HandlePhysicsBeginContact(eventType, eventData)
    if TitleMenu.IsPreviewActive() then
        TitleMenu.HandlePreviewBeginContact(eventType, eventData)
        return
    end
    Player.HandlePhysicsBeginContact(eventType, eventData)
end

function HandlePhysicsEndContact(eventType, eventData)
    if TitleMenu.IsPreviewActive() then
        TitleMenu.HandlePreviewEndContact(eventType, eventData)
        return
    end
    Player.HandlePhysicsEndContact(eventType, eventData)
end

-- ============================================================================
-- NanoVG 渲染
-- ============================================================================
function HandleRender(eventType, eventData)
    if S.nvg == nil then return end
    Renderer.HandleRender(eventType, eventData)
end
