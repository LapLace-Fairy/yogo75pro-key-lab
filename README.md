# YogoLab

YogoLab 是一款 macOS 原生工具，用 ATK YOGO 75 PRO 键盘的 6×6 点阵屏提示低电量和编程 Agent 的待确认事项，并提供打开或切换 ChatGPT、ZCode 的全局快捷键。

## 系统要求

- macOS 14 或更新版本；Xcode 和 Swift 6 用于从源码构建。
- ATK YOGO 75 PRO，使用 2.4G 接收器或有线连接。当前 2.4G 场景已实机验证，有线连接仍待验收。
- 使用 Agent 状态提醒需要配置相应 Hook；仅使用电量提醒不需要 Hook。

## 功能

### 点阵提醒

正常情况下点阵屏保持熄灭。电量下降至低于 **50% / 20% / 10%** 时，分别以黄色、橙色、红色感叹号闪烁 10 次。首次连接时若已处于低电量区间，仅提醒当前最严重的一档；电量恢复后再次下降会重新提醒。

当 Codex 或 ZCode 出现待回复或待确认事项时，分别持续显示浅蓝色 **X** 或浅黄色 **Z**，直到收到对应会话的后续处理事件。多个会话的状态会聚合；两个 Agent 同时等待时轮流显示。待确认提醒优先，低电量提醒排队等待。

Codex 和 ZCode 的 Hook 事件、三种电量图案、模拟的 X/Z 图案以及空闲熄屏已在当前 2.4G 环境中验证。真实审批、不同提问形式、多会话和有线连接仍需进一步验收；未识别或未收到的事件可能无法触发提醒。详情见 [编程状态接入](docs/hooks.md)。

### 快捷键和配置

| 快捷键 | 功能 |
| --- | --- |
| Shift + Control + Option + Command + X | 打开 ChatGPT，或切换到已运行的 ChatGPT |
| Shift + Control + Option + Command + Z | 打开 ZCode，或切换到已运行的 ZCode |

快捷键在 YogoLab 运行时生效，适用于所有键盘；界面会显示注册结果。两个应用已运行时的切换已实机验证，应用未运行时的启动尚待实机验收。实体按键映射可通过界面中的「打开 ATK HUB」进入 [ATK HUB](https://hub.atk.pro/) 配置；YogoLab 本身不修改键盘映射。

## 构建与运行

在项目目录执行：

```sh
# 构建正式版
sh scripts/build-app.sh

# 打开应用
open .build/YogoLab.app

# 运行测试
swift test
```

正式版为本机临时签名的开发构建，未经过 Apple 开发者签名或公证。它不包含灯效测试入口。项目使用系统框架，`Package.swift` 未声明第三方 Swift 包依赖。

需要测试灯效时可构建 Debug 版：

```sh
YOGO_BUILD_CONFIGURATION=debug sh scripts/build-app.sh
open '.build/YogoLab Debug.app'
```

Debug 版提供低电量灯效、Agent 待确认模拟和 75 秒空闲 CPU 测量。两种版本使用相同键盘接口，切换前请退出正在运行的版本；如果 ATK HUB 或其他驱动占用接口，也请先退出它们，再在 YogoLab 中重新检测。

受限构建环境若无法写入默认编译缓存，可将缓存指向可写目录：

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/yogo-clang-cache swift test --disable-sandbox --build-system native
```

## 配置 Agent 状态

YogoLab 不会自动修改 Codex 或 ZCode 配置。请先构建正式版，按照 [Hook 接入说明](docs/hooks.md) 合并相应事件并完成应用要求的信任或重启步骤。Hook 程序位于 `.build/YogoLab.app/Contents/MacOS/YogoSignal`；配置使用绝对路径，移动或删除应用包后需要同步更新配置。

项目也提供 `scripts/install-status-hooks.sh`，需要 `jq` 和两边已有的配置文件。脚本会修改两份配置并创建完整备份；使用前请审阅脚本与现有配置。若已配置指向旧版应用包的 Hook，不要直接重复安装，应参照接入说明迁移现有条目，避免同一事件执行两次。备份可能包含其他应用的敏感配置，不应公开分享。

## 隐私与本地数据

- `YogoSignal` 会读取并解析由 Codex 或 ZCode 通过标准输入交给 Hook 的完整事件；事件可能包含提示词、工具参数或其他敏感内容。当前实现仅提取会话标识、事件名和工具名来判断状态，不会将完整事件、提示词或工具参数写入状态文件，也不向标准输出返回审批决定。
- 状态文件默认保存在 `~/Library/Application Support/YogoKeyLab/signals/`，包含 Agent 名称、会话标识的 SHA-256 摘要、状态和时间。摘要是可关联的标识，不应视为匿名数据。目录首次创建时请求 `0700` 权限；已有目录的权限需自行检查。可在退出 YogoLab 后删除该目录以清除状态记录。
- 非等待状态在 30 分钟未更新后显示为未知；这不代表对应文件会自动删除。等待状态可能在异常退出后继续保留，直到收到后续事件或手动清理。
- 根据当前源码审查，应用自身没有实现网络上传；「打开 ATK HUB」会通过默认浏览器访问第三方网站，其数据处理遵循该网站及浏览器的行为。源码审查不构成对操作系统、其他应用或所有潜在漏洞的保证。

## 分享与安全

`.build/` 和 `.swiftpm/` 是本机生成的构建目录，已在 `.gitignore` 中排除。构建缓存、旧版应用和 Debug 二进制可能包含本机用户名或绝对路径，不应直接分享。正式构建会在签名前移除调试符号，以减少路径泄露；分享前仍应自行检查最终产物。`.gitignore` 不会移除已经被 Git 跟踪的文件，也不能代替密钥扫描。

性能测量范围见 [性能记录](docs/performance.md)，设备协议参考及第三方许可说明见 [第三方资料](THIRD_PARTY.md)。
