# 编程状态接入（实验阶段）

App 读取由 `YogoSignal` 记录的本机会话状态。已在当前 macOS 的 Codex 和 ZCode 桌面版验证实际状态事件，X/Z 图案已通过模拟事件在 2.4G 实机验证。真实审批、多会话及不同的等待用户方式仍需验证，因此不能保证覆盖所有任务。没有接入或还未收到事件时显示“未知”，点阵保持熄灭。此方案不替用户批准或拒绝任何请求。

## 准备

在项目根目录运行 `sh scripts/build-app.sh`，使用 App 包内 `Contents/MacOS/YogoSignal` 的绝对路径。以下片段中的 `SIGNAL_PATH` 是占位符，必须替换为实际路径。若路径包含空格，Codex 的 `command` 必须保留包住路径的双引号；ZCode 的 `process` 使用参数数组，无须将双引号写进路径本身。

已配置旧版路径的用户可继续保留旧版包内的辅助程序，不必重复安装 Hook；如需迁移路径，应替换现有条目，避免重复添加，再按提示信任 Codex Hook 并重启 ZCode。

不要覆盖已有配置。将条目追加到现有同名事件的数组，保留原有其他事件及设置。以下为配置片段，不会自行安装。

## Codex

参考 [Codex Hooks 文档](https://learn.chatgpt.com/docs/hooks)，用户级配置位于 `~/.codex/hooks.json`。示例展示三个事件，其余事件采用同样结构：

```json
{
  "hooks": {
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "\"SIGNAL_PATH\" codex", "timeout": 3}]}],
    "PermissionRequest": [{"hooks": [{"type": "command", "command": "\"SIGNAL_PATH\" codex", "timeout": 3}]}],
    "Stop": [{"hooks": [{"type": "command", "command": "\"SIGNAL_PATH\" codex", "timeout": 3}]}]
  }
}
```

同时以相同方式增加 `PreToolUse`、`PostToolUse`、`SessionEnd`。按照 Codex 提示审阅并信任对应 Hook；不需要绕过信任机制。Hook 配置是否适用于当前桌面版、已有会话以及云端会话，必须分别测试。

## ZCode

参考 [ZCode Hooks 文档](https://zcode.network/cn/docs/hooks/)，用户级配置位于 `~/.zcode/cli/config.json`，结构为 `hooks.enabled` 和 `hooks.events`。配置片段：

```json
{
  "hooks": {
    "enabled": true,
    "events": {
      "UserPromptSubmit": [{"hooks": [{"type": "process", "command": "SIGNAL_PATH", "args": ["zcode"], "timeoutMs": 3000}]}],
      "PermissionRequest": [{"hooks": [{"type": "process", "command": "SIGNAL_PATH", "args": ["zcode"], "timeoutMs": 3000}]}],
      "Stop": [{"hooks": [{"type": "process", "command": "SIGNAL_PATH", "args": ["zcode"], "timeoutMs": 3000}]}]
    }
  }
}
```

同时以相同方式增加 `PreToolUse`、`PostToolUse`、`PostToolUseFailure`。ZCode 在会话启动时读取配置，修改后新建会话验证。

当前本机实测时，新建会话仍使用了旧的后台配置；完全退出并重启 ZCode 后，新建会话才开始产生状态事件。

## 状态和限制

- `UserPromptSubmit`、普通 `PreToolUse`、`PostToolUse`、`PostToolUseFailure` 显示进行中；`PermissionRequest` 和已识别的提问工具显示待确认；`Stop` 表示本轮结束，不代表整个项目完成。
- 提问工具目前只识别 `request_user_input` 和 `AskUserQuestion`；其他名称、纯文本追问、桌面界面独有事件和云端事件尚未验证，可能无法显示待确认。权限请求被拒绝或取消后是否会触发恢复事件，也需要实测。
- 非等待状态超过 30 分钟没有更新时变为未知。等待状态持续显示直到收到后续事件或记录被移除；如果应用异常退出而没有结束事件，可能保留过期提醒，可删除对应信号记录。Codex 的 `SessionEnd` 会移除记录；ZCode 当前没有对应的已验证事件。
- 默认仅保存会话 ID 的 SHA-256 值、应用名称、状态和时间到 `~/Library/Application Support/YogoKeyLab/signals/`，不保存用户提示词、工具参数、审批内容或对话正文。可删除该目录清空显示记录。
- Hook 写入失败时不输出文本、不返回决定，避免阻塞或改变正常审批。`YOGO_SIGNAL_DIR` 可为 App 与 Hook 指定相同的测试目录。
