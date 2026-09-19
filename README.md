# Doubao-ime-hammerspoon

Hammerspoon 脚本，让 macOS 始终使用**豆包输入法**，并默认保持**英文模式**。

## 功能

- **锁定豆包输入法** — 被切到 ABC 等其它输入法时自动切回豆包
- **默认英文模式** — 从其它输入法回到豆包后自动按一次 Shift 进入英文
- **手动中文** — 已经在豆包时不会再自动按 Shift，需要中文时自己按 Shift
- **右 Command 双击左 Option** — 默认关掉（代码里注释着），用于触发豆包语音

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
| `TARGET_SOURCE_ID` | `com.bytedance.inputmethod.doubaoime.pinyin` | 豆包输入法 TIS ID |
| `SHIFT_AFTER_SWITCH` | `0.18` | 切到豆包后再发 Shift 的等待（秒） |
| `SHIFT_HOLD` | `0.09` | Shift tap 按下时长（秒），豆包 1.0 过短会吞 |
| `SAFETY_CHECK_INTERVAL` | `2.5` | 兜底巡检间隔（秒） |

## 原理

1. 用 `hs.keycodes.currentSourceID()` 识别当前输入法（切到 ABC 时 `currentMethod()` 是 `nil`）
2. 切回豆包优先 `currentSourceID(id)`，失败再 `setMethod(名字)`（macOS Tahoe 上后者经常失灵）
3. 只在「刚从别的输入法回到豆包」时发一次左 Shift 的 `flagsChanged` tap
4. 密码框等安全输入期间不切换、不按 Shift
5. 密码框等场景若 Shift 把系统切到了 ABC，会停用自动 Shift 并只锁回豆包

## License

MIT
