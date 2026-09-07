## Codex Float 0.2.0

Plus 套餐现在会显示 5 小时限额；其他套餐仍看本周额度。

### 这一版改进了什么

- **Plus：菜单栏和悬浮胶囊的主数字改为 5 小时剩余**  
  展开详情可同时看到 5 小时重置时间和本周剩余。
- **其他套餐不变**  
  Pro、Business 等仍然只显示本周额度，即使数据里带有短窗口也不会当成 5 小时限额。
- **没有 5 小时数据时不编造**  
  Plus 若只返回周窗口，会回退显示本周剩余。
- 继续提供 **Apple Silicon + Intel** 的 universal 安装包。

### 安装

1. 下载下方的 `CodexFloat-0.2.0-macos-universal.zip`。
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
