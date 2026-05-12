-- ============================================
-- 始终使用豆包输入法 + 右 Command 双击左 Option
-- 放到 ~/.hammerspoon/init.lua
-- ============================================
local log = hs.logger.new("ForceDoubanIME", "debug")
local alert = hs.alert

local TARGET_IME = "豆包输入法"
-- 把可能的 ABC 各种标识都列上，currentMethod() 在不同 macOS 版本下返回值不同
local SKIP_IME_LIST = {
    "ABC",
    "com.apple.keylayout.ABC",
    "U.S.",
    "com.apple.keylayout.US",
}
local SHIFT_DELAY = 0.05              -- IME 切换后到按 Shift 的等待
local SHIFT_DEDUP_WINDOW = 0.5        -- 在此时间窗内的重复 pressShift 调用会被合并为 1 次

local KEYCODE_RIGHT_CMD = 54
local OPTION_PRESS_DELAY = 0.30
local OPTION_DOUBLE_TAP_INTERVAL = 0.18

-- 切换可靠性参数
local SWITCH_VERIFY_DELAY = 0.08      -- setMethod 后回读校验间隔
local SWITCH_MAX_RETRY = 3            -- 单次切换最多重试次数
local SAFETY_CHECK_INTERVAL = 2.5     -- 兜底巡检间隔（秒）

-- ===== 右 Command 状态 =====
local rightCmdIsDown = false
local optionPressTimer = nil

-- ============================================
-- IME 工具函数
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

local function isTargetSource(source)
    return source == TARGET_IME
end

-- ============================================
-- Shift 发送：down/up 用 timer 拉开 60ms，避免同 tick 被吞
-- ============================================

local function sendShift()
    hs.eventtap.event.newKeyEvent(hs.keycodes.map.shift, true):post()
    hs.timer.doAfter(0.06, function()
        hs.eventtap.event.newKeyEvent(hs.keycodes.map.shift, false):post()
        log.df("已发送 Shift")
    end)
end

-- 去重：switchToTargetIME 成功后和 inputSourceChanged 都会调 pressShift，
-- 在此窗口内的重复调用合并为 1 次。
local lastShiftTime = 0

local function pressShift()
    local now = hs.timer.secondsSinceEpoch()
    if now - lastShiftTime < SHIFT_DEDUP_WINDOW then
        log.df("Shift 去重：距上次 %.3fs，跳过", now - lastShiftTime)
        return
    end
    lastShiftTime = now

    hs.timer.doAfter(SHIFT_DELAY, sendShift)
end

-- 真正执行一次切换 + 回读校验，失败会自我重试
-- 异步链式重试，避免阻塞主线程
local function switchToTargetIME(retryLeft)
    retryLeft = retryLeft or SWITCH_MAX_RETRY

    local before = hs.keycodes.currentMethod()
    if isTargetSource(before) then
        log.df("当前已是目标输入法，跳过切换")
        return
    end

    log.df("切换到目标输入法: %s (剩余重试 %d，切换前=%s)",
        TARGET_IME, retryLeft, tostring(before))

    local ok = hs.keycodes.setMethod(TARGET_IME)
    log.df("setMethod 返回: %s", tostring(ok))

    -- 回读校验：setMethod 返回 true 不代表真的切换成功
    hs.timer.doAfter(SWITCH_VERIFY_DELAY, function()
        local after = hs.keycodes.currentMethod()
        if isTargetSource(after) then
            log.df("切换成功，当前 = %s", tostring(after))
            pressShift()
        else
            log.wf("切换后仍非目标 IME（当前=%s），剩余重试=%d",
                tostring(after), retryLeft - 1)
            if retryLeft > 1 then
                switchToTargetIME(retryLeft - 1)
            else
                log.ef("切换失败，已用尽重试。当前=%s", tostring(after))
            end
        end
    end)
end

-- ============================================
-- 输入法变更监听
-- ============================================

local function onInputSourceChanged()
    local current = hs.keycodes.currentMethod()
    log.df("输入法变更为: %s", tostring(current))

    if isSkipSource(current) then
        log.df("检测到切换到 %s，自动切回 %s", current, TARGET_IME)
        switchToTargetIME()
    elseif isTargetSource(current) then
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
-- 兜底：App 激活 + 定时巡检
-- ============================================

local function ensureTargetIME(reason)
    local current = hs.keycodes.currentMethod()
    if not isTargetSource(current) then
        log.df("[%s] 当前=%s，非目标 IME，触发切换",
            tostring(reason), tostring(current))
        switchToTargetIME()
    end
end

local function onAppEvent(_, eventType, _)
    if eventType == hs.application.watcher.activated then
        -- macOS 会按 App 记忆 IME，激活时强校正一次
        ensureTargetIME("appActivated")
    end
end

local function safeAppEvent(name, eventType, app)
    local ok, err = xpcall(function()
        onAppEvent(name, eventType, app)
    end, debug.traceback)
    if not ok then
        log.ef("appWatcher 回调报错:\n%s", tostring(err))
    end
end

-- ============================================
-- 右 Command 双击左 Option
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
log.i("当前输入法: %s", tostring(initial))

if not isTargetSource(initial) then
    switchToTargetIME()
end

_G.inputSourceWatcher = hs.keycodes.inputSourceChanged(safeInputSourceChanged)

_G.rightCmdWatcher = hs.eventtap.new(
    { hs.eventtap.event.types.flagsChanged },
    safeEventHandler
)
_G.rightCmdWatcher:start()

_G.appWatcher = hs.application.watcher.new(safeAppEvent)
_G.appWatcher:start()

-- 兜底巡检：每隔几秒强制校正一次（最后保险）
_G.safetyTimer = hs.timer.doEvery(SAFETY_CHECK_INTERVAL, function()
    local ok, err = xpcall(function()
        ensureTargetIME("safetyTimer")
    end, debug.traceback)
    if not ok then
        log.ef("safetyTimer 回调报错:\n%s", tostring(err))
    end
end)

alert.show("ForceDoubanIME 已启动")
log.i("始终使用 %s，默认英文模式 + 右 Command 双击左 Option", TARGET_IME)


