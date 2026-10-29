# 宿主配置

内置客户端本身就是一份默认配置（[`lib/src/catalog.dart`](../lib/src/catalog.dart)），
用户手写的 [本机扩展](extensions.md) 先合并在它上面，宿主配置用**同一种格式**
最后按客户端 ID 合并。不传配置时只使用内置默认值和本机扩展（如果宿主读取了
扩展目录）。
编辑器可引用 [config.schema.json](config.schema.json) 获得补全；完整示例见
[example/config/launcher.json](../example/config/launcher.json)。

```json
{
  "$schema": "./config.schema.json",
  "schemaVersion": 1,
  "preferences": { "macosTerminal": "iterm", "itermOpenMode": "new-tab" },
  "clients": {
    "cursor": { "enabled": false },
    "pi": { "preferences": { "macosTerminal": "terminal" } },
    "opencode-cli": {
      "aliases": ["OpenCode Terminal"],
      "launch": { "command": ["opencode", "--session", "{id}"] }
    },
    "example-desktop": {
      "name": "Example Desktop",
      "launch": { "uri": "example://session/open?id={id}", "idSource": "hostSessionId" }
    }
  }
}
```

## 字段

| 字段 | 说明 |
| --- | --- |
| `schemaVersion` | 固定为 `1`。 |
| `preferences` | 全宿主的默认终端偏好。 |
| `clients.<id>` | 覆盖内置客户端，或新增一个客户端。ID 为小写字母、数字和连字符。 |
| `clients.<id>.name` | 展示名称，供设置页使用。 |
| `clients.<id>.enabled` | `false` 时仍能识别来源，但 `inspect` / `open` 返回 `client_disabled`。 |
| `clients.<id>.aliases` | 追加的来源标签（不区分大小写和标点）。新增客户端的 ID 自动成为标签。 |
| `clients.<id>.launch` | 打开方式，整体替换内置值，见下文。 |
| `clients.<id>.preferences` | 只对该客户端生效的终端偏好。 |

合并规则：列出的字段替换内置值，`aliases` 是追加，未列出的客户端和字段保持
默认。终端偏好按「请求 > 客户端 > 宿主 > 内置默认（Terminal、新窗口）」依次取值。

## 打开方式

**CLI**：`command` 是程序加固定参数，参数中恰好有一个元素是 `{id}`，运行时只
替换这一项。程序可以是 PATH 中的程序名，也可以是绝对路径或 `~/` 开头的路径
（打开时展开为当前用户主目录），不能是相对路径或 Shell 文本；参数不能包含 Shell
语法；工作目录来自会话目标。

```json
{ "command": ["kiro-cli", "chat", "--resume-id", "{id}"], "idFormat": "safe" }
```

**深链**：`uri` 是 `scheme://host/path?key=value` 模板，`{id}` 恰好出现一次，且
必须是完整的路径段或查询值；组件负责编码。不接受 `http`、`https`、`file`、
`data`、`javascript`、`mailto`，也不接受 `#` 片段。

```json
{ "uri": "codex://threads/{id}", "idFormat": "uuid" }
```

| 字段 | 取值 |
| --- | --- |
| `idSource` | 仅深链：`conversationId`（默认）或 `hostSessionId`。 |
| `idFormat` | `safe`（默认）、`uuid`；深链还可以用 `claude-desktop`、`cursor-background`。 |

## 不可放宽的约束

覆盖内置客户端时（本机扩展和宿主配置相同，始终以内置定义为准）：

- 不能改变打开类型，例如不能把 Codex Desktop 改成 CLI。
- 不能改变 `idSource`，例如 Claude Desktop 始终使用 `hostSessionId`。
- `idFormat` 只能保持或收紧（`safe` → `uuid`），Pi、Codex 等不能放宽成 `safe`。

`Claude Code`、`Codex`、`OpenCode`、`Antigravity`、`Copilot` 这类覆盖多个
产品形态的标签只能被识别，不能配置，也不能被其他客户端的别名占用；宿主需要先
取得明确的来源。OpenCode Desktop、Antigravity IDE/App、Copilot IDE、Windsurf
这类明确但没有内置打开方式的客户端，可以由宿主补充 `launch`。

## 错误

宿主配置作为整体校验，任何一处错误都返回 `invalid_configuration`，不会部分生效或
静默回退；它先单独校验，所以本机扩展不会让宿主配置失效。本机扩展按文件校验，
出错的文件被跳过并列在 `extensionErrors` 中。错误信息给出 JSON 路径和原因，例如：

```text
$.clients.pi.launch.idFormat: must stay uuid for this client.
$.clients.example-cli.launch.command: arguments must contain "{id}" exactly once.
```

## 信任边界

配置可以决定启动哪个本机程序，属于**可信输入**。它只能来自宿主自己的本机配置，
不能由网页、网络请求、未知插件或会话数据提供或修改。会话 JSON 请求不能指定
配置路径、命令或深链。原生可执行文件每次调用都会重新读取 `--config` 文件（最大
64 KiB）和 `--extensions` 目录；Dart 宿主在需要时调用 `LauncherConfig.load` 重新
构造配置。
