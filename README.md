# Agent Session Launcher

本地 Agent 会话打开组件，可供 Flutter/Dart 应用和 Node.js 宿主复用。它接收一个
**已由宿主确认来源的会话目标**，生成固定的深链或 CLI 参数；只有显式请求 `open`
时才会尝试调用操作系统打开会话。它不保存会话、不运行模型、不向 Agent 发送消息，
也不提供 HTTP 服务。

This is a local interactive session launcher with a Dart API and a one-shot JSON
protocol for Node.js and other hosts. Background Agent execution is out of scope.

## 支持范围

| 明确的客户端 | 目标 | 方式 |
| --- | --- | --- |
| `claude-desktop` | Desktop 的 `hostSessionId` | `claude://code/continue` |
| `codex-desktop` | 完整 UUID | `codex://threads/` |
| `cursor` | `bc-` 后台 Agent ID | Cursor 深链 |
| `claude-code`, `gemini-cli`, `copilot-cli`, `grok-build` | 会话 ID 和工作目录 | 各客户端的 CLI 恢复命令 |
| `pi`, `codex-cli` | 完整 UUID 和工作目录 | 各客户端的 CLI 恢复命令 |
| `opencode-cli`, `antigravity-cli`, `kiro-cli` | 会话 ID 和工作目录 | 各客户端的 CLI 恢复命令 |

`codex`、`claude-code-unknown`、`opencode`、`opencode-desktop`、通用
`antigravity`、Antigravity App/IDE、通用 Copilot 和 Windsurf 不会被猜成 CLI。
分类时，单独的 `Claude Code` 不足以区分 Desktop 与 CLI；有明确的 Desktop
entrypoint 时归为 `claude-desktop`，有明确的 `Claude Code CLI` 来源时归为 CLI。
OpenCode 的某些事件也不区分 Desktop 和 CLI，宿主必须先取得可靠来源。

macOS CLI 使用 Terminal 或 iTerm；Windows 使用 Windows Terminal。Linux 可以
生成 CLI 计划，但目前没有实现交互式终端打开。URI 路径在 macOS、Windows、Linux
分别请求系统打开；这些能力仍依赖客户端和对应系统组件实际安装。

Claude Desktop 深链来自本机行为验证，不是这里所能保证的公开稳定契约。组件不识别、
保存或切换登录账号，打开时使用目标客户端当前的登录状态与配置。`inspect` 的
`openSupported` 只表示当前平台有实现，并不验证应用、账号或会话存在。

## 下载

每个版本在 [Releases](https://github.com/JevonsCode/agent-session-launcher/releases) 提供编译好的可执行文件，不需要安装 Dart：

| 平台 | 文件 |
| --- | --- |
| macOS（Apple 芯片） | `agent-session-launcher-macos-arm64` |
| macOS（Intel） | `agent-session-launcher-macos-x64` |
| Linux x64 / arm64 | `agent-session-launcher-linux-x64`、`agent-session-launcher-linux-arm64` |
| Windows x64 | `agent-session-launcher-windows-x64.exe` |

用同目录的 `SHA256SUMS` 校验。macOS 上通过浏览器下载的文件需要先执行
`xattr -d com.apple.quarantine <文件>` 并 `chmod +x`；用 `curl` 下载的只需 `chmod +x`。
Node 宿主把下载的文件路径作为 `executable` 传给绑定即可。

## 构建与使用

需要 Dart SDK 3.10 或更高版本。DingDong、FULI 等宿主的完整接入步骤与现有设置
的字段对应见 [接入指南](docs/integration.md)。

Flutter/Dart 应用通过 Git 依赖进程内调用（包尚未发布到 pub.dev）：

```yaml
dependencies:
  agent_session_launcher:
    git:
      url: https://github.com/JevonsCode/agent-session-launcher.git
      ref: <commit-or-tag>
```

```dart
import 'package:agent_session_launcher/agent_session_launcher.dart';

final launcher = SessionLauncher(
  config: LauncherConfig.load(
    hostConfig: configText, // 可选
    extensionsDirectory: defaultExtensionsDirectory(), // 用户本机扩展
  ),
);
final client = launcher.classify('Claude Code', claudeEntrypoint: 'claude-desktop');
final target = SessionTarget(
  client: client,
  hostSessionId: 'local_example', // 示例：使用宿主实际保存的 ID
);
final plan = launcher.inspect(target); // 不启动任何程序
// 用户明确选择打开时，宿主再调用 launcher.open(target)。
```

Node.js 宿主先为目标平台构建可执行文件，再使用无依赖的绑定：

```sh
dart pub get
mkdir -p build
dart compile exe bin/agent_session_launcher.dart -o build/agent-session-launcher
```

```javascript
import { createLauncher, defaultExtensionsDirectory } from './bindings/node/index.mjs';

const launcher = createLauncher({
  executable: '/absolute/path/to/agent-session-launcher',
  configPath: '/absolute/path/to/launcher.json', // 可选
  extensionsDir: defaultExtensionsDirectory(), // 可选，用户本机扩展
});
await launcher.classify('Claude Code', { claudeEntrypoint: 'claude-desktop' });
// 'claude-desktop'；失败时以带 code 的 Error 拒绝
```

可执行文件一次从 stdin 读取一个 JSON 对象，输出一个 JSON 对象后退出；动作
`classify`、`clients`、`inspect`、`open` 及错误码见 [协议说明](docs/protocol.md)。
构建物与宿主系统、CPU 架构匹配，不能把 macOS 构建物当作 Windows/Linux 二进制
分发。仓库当前不附带预编译发布包。

## 配置

内置客户端就是一份默认配置（[`lib/src/catalog.dart`](lib/src/catalog.dart)）。宿主
用同样的格式写一份本机可信 JSON，在本机扩展之后按客户端 ID 合并：可以停用客户端、改名、追加
来源标签、替换打开方式、新增客户端，以及设置全局或单个客户端的终端偏好。

```json
{
  "schemaVersion": 1,
  "preferences": { "macosTerminal": "iterm", "itermOpenMode": "new-tab" },
  "clients": {
    "cursor": { "enabled": false },
    "opencode-cli": { "launch": { "command": ["opencode", "--session", "{id}"] } },
    "example-desktop": {
      "name": "Example Desktop",
      "launch": { "uri": "example://session/open?id={id}" }
    }
  }
}
```

用户本机的私有 Agent（内部 CLI、包装脚本、私有桌面应用）不需要宿主改设置：在
`~/.config/agent-session-launcher/clients/`（Windows 为
`%APPDATA%\agent-session-launcher\clients\`）放一个 `<客户端 ID>.json`，所有接入的
宿主都会识别。一个文件出错只跳过该文件，可以用 `agent-session-launcher check
<文件>` 自查，见 [本机扩展](docs/extensions.md)。

```json
{
  "schemaVersion": 1,
  "name": "Acme Agent",
  "aliases": ["Acme Agent CLI"],
  "launch": { "command": ["~/bin/acme-agent", "resume", "{id}"] }
}
```

配置和扩展可以指定要启动的本机程序，只能来自宿主自己的本机配置或用户自己的文件；会话请求不能指定配置
路径、命令或深链。配置作为整体校验，出错时返回 `invalid_configuration` 和出错的
JSON 路径，不会部分生效。字段、合并规则和不可放宽的约束见
[宿主配置](docs/configuration.md)，编辑器可使用 [JSON Schema](docs/config.schema.json)。

## 安装到 Agent

把产品接入（MCP、Hook、说明、Skills）装进本机 Agent 的功能在独立仓库
[agent-installer](https://github.com/JevonsCode/agent-installer)。两者共用本机扩展
目录：扩展文件里的 `install` 段由它读取，本组件忽略该段，只有 `install` 的文件也不会
成为可打开会话的客户端。

## 宿主集成边界

- 宿主负责验证来源和会话归属，再传入明确的 `client`；本组件不会通过扫描其他
  产品的数据猜测账号或迁移历史记录。
- 只允许受信任的本机交互触发 `open`。若 Web 应用需要它，必须由自己的本地服务
  验证用户操作和请求权限；本项目不暴露可由网页直接调用的开放接口。
- JSON 请求不接受可执行文件路径、命令、任意 URL、环境变量或凭据。命令和参数由
  组件的固定映射生成。Node 绑定的可执行文件路径是宿主自己的本地配置。
- `launch_requested` 只表示系统接受了启动请求，不代表客户端完成登录或恢复成功。
  超时可能产生不确定结果，宿主不得自动重试一次可能已经打开的会话。
- FULI 的后台 Agent 唤醒、授权、消息和结果处理是另一套能力；本组件不取代它。
  FULI 的 OpenCode 生命周期插件也不等同于“打开原会话”，两个宿主需要各自完成
  接线与验收。本仓库不会修改现有 DingDong 或 FULI 配置。

## 验证

```sh
dart test
dart analyze
AGENT_SESSION_LAUNCHER_BIN="$PWD/build/agent-session-launcher" node --test test/node_binding_test.mjs
```

可选的真实 Pi 测试需要将 `PI_EXECUTABLE` 指向本机 Pi；测试使用临时目录、离线
RPC 和合成会话，不发送模型请求。当前实测覆盖 macOS、Node.js 和本机 Pi；Windows
路径及调用方式仅有自动化模拟，尚未在 Windows 真机验证。

客户端参考：[OpenCode CLI](https://opencode.ai/docs/cli/)、
[Antigravity CLI](https://antigravity.google/docs/cli/commands/resume)、
[GitHub Copilot CLI](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference)、
[Grok Build CLI](https://docs.x.ai/build/cli/reference)。
