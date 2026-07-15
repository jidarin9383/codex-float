# Codex Float

[![CI](https://github.com/jidarin9383/codex-float/actions/workflows/ci.yml/badge.svg)](https://github.com/jidarin9383/codex-float/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/jidarin9383/codex-float?include_prereleases)](https://github.com/jidarin9383/codex-float/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black)](#install)
[![Swift](https://img.shields.io/badge/Swift-6-F05138.svg)](Package.swift)

**一眼看到本周 Codex 还剩多少额度。**

Codex Float 是一款原生 macOS 菜单栏 + 悬浮窗工具：用最少打扰，持续显示 weekly remaining quota，点击即可查看重置时间、当前套餐与重置机会。

> Working name: **Codex Float** · Bundle ID: `app.codexfloat.mac` · Language UI: 简体中文

---

## 为什么需要它

频繁使用 Codex 时，往往要中断工作、打开别的界面才知道额度。Codex Float 回答一个问题：

> **这周 Codex 还剩多少？**

数据来自本机已安装的 `codex app-server`，不抓网页、不代管账号、不上传使用数据。

## 功能

| 表面 | 做什么 |
|------|--------|
| **菜单栏** | Ocean Mist 品牌图标；开关悬浮窗、开机自启、检查更新、退出 |
| **悬浮窗** | 电池式胶囊，直接显示本周剩余百分比；语义色（健康 / 注意 / 危急） |
| **详情** | 下次重置（绝对时间 + 相对倒计时）、当前套餐、重置机会（有到期日时可展开） |
| **刷新** | 启动/唤醒立即刷新；默认 60 秒轮询；失败退避 15s → 5m |
| **更新** | 正式包通过 GitHub Releases API 检查新版本 |

## 截图 / 设计

设计稿与静态视觉板（实现与之一致）：

- [UI Mock](Design/ui-mock.html)
- [Fixture QA board](Design/fixture-qa.html)
- [Brand board](Design/brand-board.html)
- 品牌资源：[`Assets/Brand/v2/`](Assets/Brand/v2/)

视觉方向：**macOS Tahoe liquid glass** + **Ocean Mist** 配色。

## Install

### 从 Release 安装（推荐）

1. 打开 [Releases](https://github.com/jidarin9383/codex-float/releases/latest)，下载 `CodexFloat-*-macos-*.zip`
2. 解压，将 **Codex Float.app** 拖到「应用程序」
3. 若系统提示无法打开（开源 ad-hoc 签名，尚未公证）：  
   **右键 app → 打开 → 打开**
4. 本机需已安装并登录 [Codex CLI](https://github.com/openai/codex)

当前 CI 产物面向 **Apple Silicon (arm64)**。Intel Mac 请从源码构建。

### 从源码打包

```bash
git clone https://github.com/jidarin9383/codex-float.git
cd codex-float
chmod +x scripts/*.sh
./scripts/package-app.sh
open "dist/Codex Float.app"
```

可选环境变量：

```bash
VERSION=0.1.0 \
BUILD_NUMBER=1 \
CODEX_FLOAT_GITHUB_REPO=jidarin9383/codex-float \
./scripts/package-app.sh
```

### Xcode 调试

```bash
./scripts/open-xcode.sh
# Scheme: CodexFloat → My Mac → ⌘R
```

### 命令行开发

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # 如需要

swift build
swift run CodexFloatCoreSmokeTests
CODEX_FLOAT_LIVE_PROTOCOL=1 swift run CodexFloatCoreSmokeTests   # 可选：真机协议探测
swift run CodexFloat
CODEX_FLOAT_STATIC_FIXTURES=1 swift run CodexFloat               # 仅静态 UI
```

## 要求

- macOS 14+
- Swift 6 / Xcode（UI 调试推荐完整 Xcode）
- 本机 Codex CLI（实时额度）

## 隐私与安全

- **不**读取、复制、打印或持久化 Codex 登录凭证内容到本应用存储
- 启动 `codex` 使用 `Process` + 结构化参数，不拼 shell 命令字符串
- 重置机会到期日：仅在内存中使用本机 Codex 登录态请求 HTTPS，失败不影响主额度
- **无遥测**，数据默认不出本机

详见 [`AGENTS.md`](AGENTS.md)、[`Tech-Spec.md`](Tech-Spec.md)。

## 架构

```text
MenuBarExtra / Floating NSPanel
        → QuotaViewModel
        → QuotaRepository
        → CodexAppServerClient      (JSONL / app-server --stdio)
        → codex（本机）
        ↘ ChatGPTQuotaClient       （可选：重置机会到期日）
```

| 文档 | 内容 |
|------|------|
| [`PRD.md`](PRD.md) | 产品需求 |
| [`Tech-Spec.md`](Tech-Spec.md) | 工程规格 |
| [`DESIGN.md`](DESIGN.md) | 视觉与交互 |
| [`MEMORY.md`](MEMORY.md) | 决策记录 |

## 开发进度

| Step | 范围 | 状态 |
|------|------|------|
| 1 | 静态 UI | ✅ |
| 2 | Ocean Mist v2 品牌 | ✅ |
| 3 | 协议客户端 + Repository | ✅ |
| 4 | 实时额度接入 | ✅ |
| 5 | GitHub 打包 / CI / Releases / 检查更新 | ✅（开源 ad-hoc；公证延后） |

## 维护者：发版

```bash
./scripts/package-app.sh          # 本地验收产物
git tag v0.1.1
git push origin v0.1.1            # 触发 release workflow
```

- CI：[`.github/workflows/ci.yml`](.github/workflows/ci.yml) — 每次 push/PR 构建 + smoke + 上传 zip artifact  
- Release：[`.github/workflows/release.yml`](.github/workflows/release.yml) — `v*` tag 发布

## 贡献

欢迎 Issue / PR。请先阅读 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

提交信息与技术文档使用 **English**；产品 UI 文案保持 **简体中文**。

## 许可证

[MIT](LICENSE) © Codex Float contributors

---

**Not affiliated with OpenAI.** Codex is a trademark of its respective owners. This project only talks to your locally installed Codex CLI.
