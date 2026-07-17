## Codex Float 0.1.2

修复悬浮胶囊「电量」颜色，让剩余额度一眼可读；并保持 universal 安装包。

### 这一版改进了什么

- **胶囊填色按剩余额度正确分档**
  - **> 50%**：绿色
  - **> 20% 且 ≤ 50%**：橙色
  - **≤ 20%**：红色
- **数据过期时不再把整条填色改成黄色**  
  过期只在菜单栏小点 / 详情状态条提示；胶囊仍按剩余百分比显示绿 / 橙 / 红。
- 填色使用更易辨认的固定色值，在液态玻璃背景上更清晰。
- 继续提供 **Apple Silicon + Intel** 的 universal 安装包。

### 安装

1. 下载下方的 `CodexFloat-0.1.2-macos-universal.zip`。
2. 解压后，将 **Codex Float.app** 拖入「应用程序」文件夹（覆盖旧版即可）。
3. 确认这台 Mac 已安装并登录 [Codex CLI](https://github.com/openai/codex)。
4. 打开 Codex Float。

### 如果 macOS 提示无法打开

当前版本尚未经过 Apple 公证。请确认安装包来自本页面，然后：

1. 先尝试打开一次 **Codex Float.app**。
2. 打开「系统设置 → 隐私与安全性」。
3. 向下滚动到「安全性」，点击 Codex Float 旁边的「仍要打开」。
4. 在确认窗口中再次点击「打开」。

详细说明可查看 [Apple 官方指南](https://support.apple.com/guide/mac-help/open-an-app-by-overriding-security-settings-mh40617/mac)。

### 使用要求

- macOS 14 或更高版本
- Apple Silicon 或 Intel Mac
- 已安装并登录 Codex CLI

### 隐私

- 额度通过这台 Mac 上已登录的 Codex CLI 获取。
- 登录凭证不会写入 Codex Float 的存储、日志或诊断信息。
- 没有遥测，也不会向开发者发送额度或使用数据。

---

**Codex Float is not affiliated with OpenAI.** Codex is a trademark of its respective owners.
