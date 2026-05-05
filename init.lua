-- ============================================
-- 始终使用豆包输入法 + 右 Command 双击左 Option
-- 放到 ~/.hammerspoon/init.lua
-- ============================================
local log = hs.logger.new("ForceDoubanIME", "debug")
local alert = hs.alert

local TARGET_IME = "豆包输入法"
local SKIP_IME_LIST = { "ABC", "com.apple.keylayout.ABC" }
local SHIFT_DELAY = 0.05

local KEYCODE_RIGHT_CMD = 54
local OPTION_PRESS_DELAY = 0.30
local OPTION_DOUBLE_TAP_INTERVAL = 0.18

local lastSource = nil
local isProcessing = false

-- ===== 右 Command 状态 =====
local rightCmdIsDown = false
local optionPressTimer = nil

-- ============================================
-- IME 监听部分
-- ============================================

local function isSkipSource(source)
    if source == nil then
        return false
    end
    for _, name in ipairs(SKIP_IME_LIST) do
        if source == name then
            return true
        end
    end
    return false
end

local function pressShift()
    hs.timer.doAfter(SHIFT_DELAY, function()
        hs.eventtap.event.newKeyEvent(hs.keycodes.map.shift, true):post()
        hs.eventtap.event.newKeyEvent(hs.keycodes.map.shift, false):post()
        log.df("已发送 Shift 按键")
    end)
end

local function switchToTargetIME()
    if isProcessing then
        return
    end
    isProcessing = true

    log.df("切换到目标输入法: %s", TARGET_IME)
    local ok = hs.keycodes.setMethod(TARGET_IME)
    log.df("切换结果: %s", tostring(ok))

    if ok then
        pressShift()
    end

    isProcessing = false
end

local function onInputSourceChanged()
    if isProcessing then
        return
    end

    local current = hs.keycodes.currentMethod()

    if current == lastSource then
        return
    end
    lastSource = current

    log.df("输入法变更为: %s", tostring(current))

    if isSkipSource(current) then
        log.df("检测到切换到 %s，自动切回 %s", current, TARGET_IME)
        switchToTargetIME()
    elseif current == TARGET_IME then
        pressShift()
    end
end

local function safeInputSourceChanged()
    local ok, err = xpcall(onInputSourceChanged, debug.traceback)
    if not ok then
        log.ef("输入法回调报错:\n%s", tostring(err))
    end
end

-- ============================================
-- 右 Command 双击左 Option 部分
-- ============================================

local function tapLeftOptionOnce()
    hs.eventtap.event.newKeyEvent(hs.keycodes.map.alt, true):post()
    hs.eventtap.event.newKeyEvent(hs.keycodes.map.alt, false):post()
end

local function doubleTapLeftOption()
    log.df("双击左 Option")
    tapLeftOptionOnce()

    hs.timer.doAfter(OPTION_DOUBLE_TAP_INTERVAL, function()
        tapLeftOptionOnce()
        log.df("双击左 Option 完成")
    end)
end

local function cancelOptionTimer()
    if optionPressTimer then
        optionPressTimer:stop()
        optionPressTimer = nil
    end
end

local function onRightCmdDown()
    if rightCmdIsDown then
        return
    end
    rightCmdIsDown = true
    log.df("右 Command 按下")

    switchToTargetIME()

    cancelOptionTimer()
    optionPressTimer = hs.timer.doAfter(OPTION_PRESS_DELAY, function()
        optionPressTimer = nil
        if rightCmdIsDown then
            doubleTapLeftOption()
        end
    end)
end

local function onRightCmdUp()
    if not rightCmdIsDown then
        return
    end
    rightCmdIsDown = false
    log.df("右 Command 松开")

    cancelOptionTimer()
    doubleTapLeftOption()
end

local function handleRightCmdFlagsChanged(event)
    local keycode = event:getKeyCode()

    if keycode ~= KEYCODE_RIGHT_CMD then
        return false
    end

    if rightCmdIsDown then
        onRightCmdUp()
    else
        onRightCmdDown()
    end

    return false
end

local function safeEventHandler(event)
    local ok, result = xpcall(function()
        return handleRightCmdFlagsChanged(event)
    end, debug.traceback)

    if not ok then
        log.ef("eventtap 回调报错:\n%s", tostring(result))
        return false
    end

    return result
end

-- ============================================
-- 启动
-- ============================================

local initial = hs.keycodes.currentMethod()
lastSource = initial
log.i("当前输入法: %s", tostring(initial))

if isSkipSource(initial) then
    switchToTargetIME()
end

_G.inputSourceWatcher = hs.keycodes.inputSourceChanged(safeInputSourceChanged)
_G.rightCmdWatcher = hs.eventtap.new({hs.eventtap.event.types.flagsChanged}, safeEventHandler)
_G.rightCmdWatcher:start()

alert.show("ForceDoubanIME 已启动")
log.i("始终使用 %s，默认英文模式 + 右 Command 双击左 Option", TARGET_IME)
