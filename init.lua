-- =======================================================
-- 豆包语音极简助手：语音录音结束 -> 等文字上屏 -> 切回 ABC
-- 机制：麦克风硬件状态判断录音起止（不拦按键）
--       麦克风停只代表录音结束，转写往往还在跑；
--       再等焦点文本稳定后才切 ABC，避免长语音被掐掉
--       切换到其他 App 时默认 ABC（录音中除外）
-- =======================================================
require("hs.ipc")

local ABC_SOURCE_ID = "com.apple.keylayout.ABC"

-- 短语音：转写几乎立刻结束，固定再等一小会即可
local SHORT_DURATION = 1.8
local SHORT_COMMIT_DELAY = 0.4

-- 长语音：能读到焦点文本时等上屏稳定；读不到则固定约 1s
local POLL_INTERVAL = 0.1
local TEXT_STABLE_FOR = 0.6 -- 文本连续稳定多久视为上屏完成
local MIN_WAIT_BASE = 0.5
local MIN_WAIT_PER_SEC = 0.08
local MIN_WAIT_CAP = 2.2
local MAX_WAIT_BASE = 2.0
local MAX_WAIT_PER_SEC = 0.4
local MAX_WAIT_CAP = 12.0
local FALLBACK_DELAY = 1.0 -- 终端等读不到文本的 App，停麦后约 1s 切 ABC

local log = hs.logger.new("DoubaoVoice", "info")

local function logf(fmt, ...)
    log.i(string.format(fmt, ...))
end

local wasRecording = false
local recordStartedAt = nil
local streamingLikely = false
local recordPoll = nil
local commitTimer = nil

local function isDoubaoIME()
    local curIME = hs.keycodes.currentSourceID() or ""
    return string.find(curIME, "doubao") ~= nil
end

local function isDoubaoApp(app)
    if not app then
        return false
    end
    local bid = (app:bundleID() or ""):lower()
    local name = app:name() or ""
    return string.find(bid, "doubao") ~= nil or string.find(name, "豆包") ~= nil
end

local function isAnyMicInUse()
    local devs = hs.audiodevice.allInputDevices()
    for _, d in ipairs(devs) do
        if d:inUse() then
            return true
        end
    end
    return false
end

-- 读焦点控件文本指纹。hs.uielement 没有 attributeValue，必须走 axuielement。
local function fingerprintFocusedText()
    local ok, fp = pcall(function()
        local sys = hs.axuielement.systemWideElement()
        local el = sys:attributeValue("AXFocusedUIElement")
        if not el then
            local app = hs.application.frontmostApplication()
            if app then
                local appEl = hs.axuielement.applicationElement(app)
                el = appEl and appEl:attributeValue("AXFocusedUIElement")
            end
        end
        if not el then
            return nil
        end

        local role = el:attributeValue("AXRole")
        if role == "AXWindow" or role == "AXApplication" then
            return nil
        end

        local v = el:attributeValue("AXValue")
        if type(v) ~= "string" then
            local n = el:attributeValue("AXNumberOfCharacters")
            if type(n) == "number" then
                return tostring(n)
            end
            return nil
        end
        local n = #v
        if n > 120 then
            return n .. "\0" .. string.sub(v, -120)
        end
        return n .. "\0" .. v
    end)
    if not ok then
        return nil
    end
    return fp
end

local function stopTimer(timer)
    if timer then
        timer:stop()
    end
    return nil
end

local function stopRecordPoll()
    recordPoll = stopTimer(recordPoll)
    _G.DoubaoRecordPoll = nil
end

local function stopCommitTimer()
    commitTimer = stopTimer(commitTimer)
    _G.DoubaoCommitTimer = nil
end

local function switchToABC(reason)
    stopCommitTimer()
    stopRecordPoll()
    if isDoubaoIME() then
        logf("切回 ABC（%s）", reason or "done")
        hs.keycodes.currentSourceID(ABC_SOURCE_ID)
    else
        logf("已不在豆包，跳过切换（%s）", reason or "done")
    end
end

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

local function minWaitFor(duration)
    return clamp(MIN_WAIT_BASE + duration * MIN_WAIT_PER_SEC, MIN_WAIT_BASE, MIN_WAIT_CAP)
end

local function maxWaitFor(duration)
    return clamp(MAX_WAIT_BASE + duration * MAX_WAIT_PER_SEC, 2.0, MAX_WAIT_CAP)
end

local function startRecordPoll()
    stopRecordPoll()
    streamingLikely = false
    local lastFp = fingerprintFocusedText()
    local changeCount = 0

    recordPoll = hs.timer.doEvery(0.2, function()
        if not wasRecording then
            stopRecordPoll()
            return
        end
        local fp = fingerprintFocusedText()
        if fp and lastFp and fp ~= lastFp then
            changeCount = changeCount + 1
            lastFp = fp
            if changeCount >= 2 then
                streamingLikely = true
            end
        elseif fp then
            lastFp = fp
        end
    end)
    _G.DoubaoRecordPoll = recordPoll
end

local function beginWaitForCommit(duration)
    stopCommitTimer()
    stopRecordPoll()

    if duration <= SHORT_DURATION then
        logf("短语音 %.1fs，%.2fs 后切 ABC", duration, SHORT_COMMIT_DELAY)
        commitTimer = hs.timer.doAfter(SHORT_COMMIT_DELAY, function()
            switchToABC("short")
        end)
        _G.DoubaoCommitTimer = commitTimer
        return
    end

    local t0 = hs.timer.secondsSinceEpoch()
    local minWait = minWaitFor(duration)
    local maxWait = maxWaitFor(duration)
    local lastFp = fingerprintFocusedText()
    local axUsable = lastFp ~= nil
    local lastChangeAt = t0
    local sawChange = false

    if not axUsable then
        logf("长语音 %.1fs，读不到文本，fallback %.2fs 后切 ABC", duration, FALLBACK_DELAY)
        commitTimer = hs.timer.doAfter(FALLBACK_DELAY, function()
            switchToABC("fallback")
        end)
        _G.DoubaoCommitTimer = commitTimer
        return
    end

    logf(
        "长语音 %.1fs，等文本稳定（流式=%s，最少 %.1fs / 最多 %.1fs）",
        duration,
        tostring(streamingLikely),
        minWait,
        maxWait
    )

    commitTimer = hs.timer.doEvery(POLL_INTERVAL, function()
        if wasRecording or isAnyMicInUse() then
            stopCommitTimer()
            return
        end

        local now = hs.timer.secondsSinceEpoch()
        local elapsed = now - t0
        local fp = fingerprintFocusedText()
        if fp and fp ~= lastFp then
            lastFp = fp
            lastChangeAt = now
            sawChange = true
        end

        local stable = (now - lastChangeAt) >= TEXT_STABLE_FOR
        if elapsed >= maxWait then
            switchToABC("timeout")
            return
        end
        if elapsed < minWait or not stable then
            return
        end

        -- 边说边出字：停麦后文本多半已经在，稳定即可切
        -- 停麦后才出字：等到真正出现过一次变化，再稳定
        if streamingLikely or sawChange then
            switchToABC(sawChange and "text-stable" or "stream-stable")
        end
    end)
    _G.DoubaoCommitTimer = commitTimer
end

local function onAudioChange()
    local curInUse = isAnyMicInUse()

    if curInUse and isDoubaoIME() then
        stopCommitTimer()
        if not wasRecording then
            wasRecording = true
            recordStartedAt = hs.timer.secondsSinceEpoch()
            logf("豆包开始录音")
            startRecordPoll()
        end
        return
    end

    if (not curInUse) and wasRecording then
        wasRecording = false
        local duration = 0
        if recordStartedAt then
            duration = hs.timer.secondsSinceEpoch() - recordStartedAt
        end
        recordStartedAt = nil
        logf("豆包录音结束，时长 %.1fs", duration)
        beginWaitForCommit(duration)
    end
end

-- 为所有音频输入设备绑定系统硬件级监听
local audioWatchers = {}
local function setupAudioWatchers()
    for _, watcher in ipairs(audioWatchers) do
        watcher:watcherStop()
    end
    audioWatchers = {}

    local devs = hs.audiodevice.allInputDevices()
    for _, dev in ipairs(devs) do
        local watcher = dev:watcherCallback(function()
            onAudioChange()
        end)
        watcher:watcherStart()
        table.insert(audioWatchers, watcher)
    end
    _G.DoubaoVoiceAudioWatchers = audioWatchers
end

setupAudioWatchers()

-- 当有新音频设备插入/拔出时重新绑定
_G.deviceWatcher = hs.audiodevice.watcher.setCallback(function(event)
    if event == "dev#" then
        setupAudioWatchers()
    end
end)
hs.audiodevice.watcher.start()

-- 切到其他 App 时默认 ABC（录音中不打断；忽略豆包自己的进程）
local function onAppActivated(appName, eventType, app)
    if eventType ~= hs.application.watcher.activated then
        return
    end
    if isDoubaoApp(app) then
        return
    end
    if wasRecording or isAnyMicInUse() then
        logf("切 App（%s），正在录音，保持豆包", appName or "?")
        return
    end
    if isDoubaoIME() then
        switchToABC("app-switch:" .. (appName or "?"))
    end
end

_G.DoubaoAppWatcher = hs.application.watcher.new(onAppActivated)
_G.DoubaoAppWatcher:start()

-- 配置修改自动重载
_G.DoubaoConfigWatcher = hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", hs.reload):start()

hs.alert.show("豆包语音极简版已启动")
