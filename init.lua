-- =======================================================
-- 豆包语音极简助手：语音录音结束 -> 自动切回 ABC
-- 机制：监听麦克风硬件状态（零按键拦截、零定时轮询、极简纯粹）
-- =======================================================
require("hs.ipc")

local ABC_SOURCE_ID = "com.apple.keylayout.ABC"
local COMMIT_DELAY = 0.25 -- 录音停止后等待 250ms 让豆包文字上屏，再切回 ABC

local wasRecording = false

-- 检查当前是否任意麦克风在使用
local function isAnyMicInUse()
    local devs = hs.audiodevice.allInputDevices()
    for _, d in ipairs(devs) do
        if d:inUse() then
            return true
        end
    end
    return false
end

-- 麦克风状态变动处理
local function onAudioChange()
    local curInUse = isAnyMicInUse()
    local curIME = hs.keycodes.currentSourceID() or ""
    local isDoubao = string.find(curIME, "doubao") ~= nil

    if curInUse and isDoubao then
        -- 豆包正在录音
        wasRecording = true
    elseif not curInUse and wasRecording then
        -- 豆包录音结束！
        wasRecording = false
        hs.timer.doAfter(COMMIT_DELAY, function()
            hs.keycodes.currentSourceID(ABC_SOURCE_ID)
        end)
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
end

setupAudioWatchers()

-- 当有新音频设备插入/拔出时重新绑定
_G.deviceWatcher = hs.audiodevice.watcher.setCallback(function(event)
    if event == "dev#" then
        setupAudioWatchers()
    end
end)
hs.audiodevice.watcher.start()

-- 全局引用防 GC
_G.DoubaoVoiceAudioWatchers = audioWatchers

-- 配置修改自动重载
_G.DoubaoConfigWatcher = hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", hs.reload):start()

hs.alert.show("豆包语音极简版已启动")
