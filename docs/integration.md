# 接入指南

宿主只需要做三件事：

1. **提供配置**：把宿主自己的设置转换成一份 [宿主配置](configuration.md)，或直接
   不传，使用内置默认值。
2. **识别来源**：用 `classify` 把 hook / 事件里的来源标签变成明确的客户端 ID，
   与会话 ID、工作目录一起保存。
3. **打开会话**：展示前用 `inspect` 判断能否打开；用户明确点击后再调用 `open`。

设置页可以用 `clients` 列出所有明确的客户端，包含名称、是否启用、打开类型、
需要哪种 ID、是否需要工作目录，以及当前平台是否实现了打开方式。

本组件不负责：会话的保存和归属校验、用户授权、Codex 子 Agent 判断这类宿主
特有的预检，以及只打开工作目录（不恢复具体会话）的行为。这些继续留在宿主里。

## Dart / Flutter（DingDong）

进程内直接调用，不需要原生可执行文件。依赖建议固定到一个提交或标签：

```yaml
dependencies:
  agent_session_launcher:
    git:
      url: https://github.com/JevonsCode/agent-session-launcher.git
      ref: <commit-or-tag>
```

```dart
import 'package:agent_session_launcher/agent_session_launcher.dart';

final LauncherConfig config = await configFile.exists()
    ? LauncherConfig.decode(await configFile.readAsString())
    : LauncherConfig.defaults;
final SessionLauncher launcher = SessionLauncher(config: config);

// 记录活动时
final String client = launcher.classify(source, claudeEntrypoint: entrypoint);

// 渲染「打开会话」按钮前
final SessionTarget target = SessionTarget(
  client: client,
  conversationId: conversationId,
  hostSessionId: hostSessionId,
  workspacePath: workspacePath,
);
bool canOpen;
try {
  canOpen = launcher.supportsOpening(launcher.inspect(target));
} on SessionLaunchException {
  canOpen = false;
}

// 用户点击后
await launcher.open(target);
```

DingDong 现有的 `AgentLauncherConfiguration` 可以一一对应：

| DingDong | 本组件 |
| --- | --- |
| `defaults.macosTerminal` / `defaults.itermOpenMode` | `preferences.*` |
| `agents.<client>.*` | `clients.<id>.preferences.*` |
| `AgentClient.codex`（`codex://threads/`） | `codex-desktop` |
| `AgentClient.claudeCode`（`claude --resume`） | `claude-code` |
| `AgentClient.geminiCli` | `gemini-cli` |
| `AgentClient.cursor`（`bc-` 后台 Agent） | `cursor` |
| `AgentClient.kiro`（`kiro-cli`） | `kiro-cli` |

DingDong 目前用 `contains('claude')` 等方式归类来源；接入后应改用 `classify`，
否则无法区分 Claude Desktop 与 Claude Code CLI。Codex 可打开性预检、Cursor/Kiro
只打开工作目录的回退仍由 DingDong 自己实现。

## Node.js（FULI）

绑定是一个无依赖的 ES 模块（尚未发布到 npm），可复制 `bindings/node/` 或以 Git
子模块引入。再为每个目标平台编译原生可执行文件并随宿主分发（构建物与系统、CPU
架构对应）：

```sh
dart compile exe bin/agent_session_launcher.dart -o build/agent-session-launcher
```

```javascript
import { createLauncher } from './vendor/agent-session-launcher/index.mjs';

const launcher = createLauncher({
  executable: '/absolute/path/to/agent-session-launcher',
  configPath: '/absolute/path/to/fuli-launcher.json', // 可选，由宿主维护
});

const client = await launcher.classify('Claude Code', { claudeEntrypoint: 'claude-desktop' });
const clients = await launcher.clients(); // 设置页
const { plan, openSupported } = await launcher.inspect(target);
await launcher.open(target); // 仅在用户明确操作后
```

失败时 Promise 以带 `code` 的 `Error` 拒绝，`code` 与 [协议](protocol.md) 的错误码
一致。`unknown_outcome` 表示超时，系统可能已经打开会话，不要自动重试。
TypeScript 类型见 `bindings/node/index.d.ts`。需要原始 JSON 时仍可使用
`requestLauncher`。

FULI 的 `conversationLaunchers` 设置可以在写入时生成宿主配置：

| FULI | 本组件 |
| --- | --- |
| `<application>.enabled` | `clients.<id>.enabled` |
| `<application>.appName` | `clients.<id>.name` |
| `<application>.urlTemplate` | `clients.<id>.launch.uri` |
| `<application>.idFormat: 'any'` | `idFormat: 'safe'` |
| `codex` | `codex-desktop` |
| `claude_code` / `claude` | 先用 `classify` 区分 `claude-code` / `claude-desktop` |
| `cursor`、`gemini_cli`、`kiro` | `cursor`、`gemini-cli`、`kiro-cli` |
| `other` | 宿主自定义 ID，例如 `example-desktop` |

FULI 的 URL 模板和本组件的 `uri` 写法相同；本组件额外要求 `{id}` 是完整的路径段
或查询值，并拒绝 Web、文件和脚本协议。FULI 后台 Agent 唤醒、消息和结果处理是
另一套能力，本组件只负责打开交互式会话。

## 验收

宿主接入后需要分别验证：来源识别是否正确、`inspect` 的计划是否符合预期、真实
点击是否打开了对应客户端的对应会话。`launch_requested` 只代表操作系统接受了请求，
不代表客户端已经登录或恢复成功。
