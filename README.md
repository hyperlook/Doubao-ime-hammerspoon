# Doubao-ime-hammerspoon

Hammerspoon 脚本，让 macOS 始终使用**豆包输入法**，并默认保持**英文模式**。

## 功能

- **锁定豆包输入法** — 自动切回 ABC 时自动切回豆包输入法
- **默认英文模式** — 切换到豆包输入法后自动按 Shift 进入英文状态
- **右 Command 双击左 Option** — 按下右 Command 键时模拟双击左 Option（用于触发豆包语音长时输入。）

## 安装

1. 安装 [Hammerspoon](https://www.hammerspoon.org/)

```bash
brew install --cask hammerspoon
```
2. 将 `init.lua` 复制到 `~/.hammerspoon/` 目录
3. 在 Hammerspoon 中 Reload Config

```bash
cp init.lua ~/.hammerspoon/init.lua
```

## 配置

在 `init.lua` 中可修改以下参数：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `TARGET_IME` | `豆包输入法` | 目标输入法名称 |
| `SKIP_IME_LIST` | `{"ABC", "com.apple.keylayout.ABC"}` | 自动切回的输入法列表 |
| `OPTION_PRESS_DELAY` | `0.30` | 按住右 Command 多久后触发双击 Option（秒） |
| `OPTION_DOUBLE_TAP_INTERVAL` | `0.18` | 两次 Option 按键间隔（秒） |

## 原理

1. 通过 `hs.keycodes.inputSourceChanged` 监听输入法切换事件
2. 检测到被强制的输入法（如 ABC）时，调用 `hs.keycodes.setMethod()` 切回目标输入法
3. 切到目标输入法后延迟发送 Shift 按键，确保英文模式
4. 通过 `hs.eventtap` 监听右 Command 的 `flagsChanged` 事件，模拟双击左 Option

## License

MIT
