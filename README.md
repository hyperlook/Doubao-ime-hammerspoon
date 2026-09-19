# Doubao-ime-hammerspoon

面向 macOS 豆包输入法的 Hammerspoon 辅助模块。

## 功能特性

- **录音结束自动切回 ABC**：监听麦克风硬件状态，录音停止并等待文字上屏稳定后，自动切换为系统英文（ABC）输入法，无需手动按键。
- **智能等待上屏（防截断）**：
  - 短语音固定短暂等待即切回；
  - 长语音自动检测焦点控件文本稳定状态，避免长文本还在流式转写时被掐断。
- **切应用自动切回 ABC**：当切换到其他应用程序时，自动切回 ABC（录音进行中除外，不打扰正在进行的语音输入）。
- **标准模块化设计**：作为独立模块加载，提供生命周期管理（`start()` / `stop()`），不侵占 Hammerspoon 全局入口。

## 安装与使用

### 1. 安装 Hammerspoon

```bash
brew install --cask hammerspoon
```

### 2. 引入模块

将本项目克隆到 `~/.hammerspoon/Doubao-ime-hammerspoon`：

```bash
git clone https://github.com/hyperlook/Doubao-ime-hammerspoon.git ~/.hammerspoon/Doubao-ime-hammerspoon
```

在你的 `~/.hammerspoon/init.lua` 中直接引用：

```lua
-- ~/.hammerspoon/init.lua

-- 加载豆包语音助手模块（默认加载即启动）
local doubaoVoice = require("Doubao-ime-hammerspoon")

-- 也可随时手动控制：
-- doubaoVoice.stop()
-- doubaoVoice.start()
```

### 3. 重载配置

在 Hammerspoon 菜单栏点击 **Reload Config**，或使用快捷键重载。

## 权限要求

由于脚本需要检测音频输入状态以及读取焦点文本变化以判断转写是否完成，请确保在 **系统设置 -> 隐私与安全性** 中为 Hammerspoon 授予以下权限：
- **辅助功能 (Accessibility)**：用于读取焦点输入框文本变化以精准判断上屏时机
- **麦克风 (Microphone)**：用于感知麦克风硬件是否在使用

## License

MIT
