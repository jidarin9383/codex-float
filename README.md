# Codex Float

[![Release](https://img.shields.io/github/v/release/jidarin9383/codex-float?include_prereleases)](https://github.com/jidarin9383/codex-float/releases/latest)
[![Platform](https://img.shields.io/badge/macOS-14%2B-black)](#系统要求)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**一眼看清 Codex 本周还剩多少额度。**

Codex Float 是一款原生 macOS 小工具。它把 Codex 本周剩余额度放在桌面悬浮窗中，需要更多信息时，点一下即可查看重置时间、当前套餐和重置机会。

[下载最新版](https://github.com/jidarin9383/codex-float/releases/latest)

## 功能

- **额度一眼可见**：悬浮窗持续显示本周剩余百分比，不用反复打开网页。
- **安静地待在桌面上**：悬浮窗保持在桌面，也可以随时从菜单栏关闭。
- **需要时再展开**：点击悬浮窗查看下次重置时间、当前套餐和可用重置机会。
- **自动保持更新**：应用会自动刷新；数据过期或读取失败时会明确提示，不把旧数据伪装成最新状态。
- **常用操作集中在菜单栏**：快速控制悬浮窗、开机自启、检查更新或退出应用。

## 安装

1. 前往 [Releases](https://github.com/jidarin9383/codex-float/releases/latest)，下载最新的 `CodexFloat-*-macos-arm64.zip`。
2. 解压后，将 **Codex Float.app** 拖入「应用程序」文件夹。
3. 打开 Codex Float。应用会自动读取当前 Mac 上的 Codex 额度。

### 如果 macOS 提示无法打开

当前下载版本尚未经过 Apple 公证。请确认安装包来自本仓库的 [Releases](https://github.com/jidarin9383/codex-float/releases/latest)，然后：

1. 先尝试打开一次 **Codex Float.app**。
2. 打开「系统设置 → 隐私与安全性」。
3. 向下滚动到「安全性」，点击 Codex Float 旁边的「仍要打开」。
4. 在确认窗口中再次点击「打开」。

「仍要打开」通常只会在尝试启动应用后的一段时间内出现。详细说明可查看 [Apple 官方指南](https://support.apple.com/guide/mac-help/open-an-app-by-overriding-security-settings-mh40617/mac)。

## 系统要求

- macOS 14 或更高版本
- Apple Silicon Mac（当前 Release 提供 `arm64` 安装包）
- 已安装并登录 [Codex CLI](https://github.com/openai/codex)

Intel Mac 暂无预编译版本。源码构建与开发说明见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 使用

- 点击悬浮窗，展开额度详情。
- 点击详情右上角的收起按钮，返回紧凑悬浮窗。
- 点击菜单栏中的 Codex Float 图标，控制悬浮窗、开机自启、检查更新或退出应用。

首次启动时，菜单栏图标和悬浮窗默认都会显示。

## 隐私

- 额度通过这台 Mac 上已登录的 Codex CLI 获取。
- 登录凭证不会写入 Codex Float 的存储、日志或诊断信息。
- 重置机会的到期时间仅在需要时通过 ChatGPT 官方接口读取，相关登录信息只在请求期间保留于内存。
- 没有遥测，也不会向开发者发送额度或使用数据。

## 开源与贡献

Codex Float 采用 [MIT License](LICENSE) 开源。问题和建议可以提交到 [Issues](https://github.com/jidarin9383/codex-float/issues)，参与开发请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

---

**Codex Float is not affiliated with OpenAI.** Codex is a trademark of its respective owners.
