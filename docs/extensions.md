# 本机扩展

本机上的 Agent 如果不在内置列表里，比如公司内部 CLI、自己写的包装脚本或私有
桌面应用，可以写一个 JSON 文件让它被识别和打开。只要宿主接入时读取了这个目录，
所有宿主都会生效，不需要分别配置。

## 放在哪里

| 平台 | 目录 |
| --- | --- |
| macOS / Linux | `~/.config/agent-clients/extensions/`；设置了 `XDG_CONFIG_HOME` 时为 `$XDG_CONFIG_HOME/agent-clients/extensions/` |
| Windows | `%APPDATA%\agent-clients\extensions\` |

`agent-clients` 是本组件与 [agent-installer](https://github.com/JevonsCode/agent-installer)
共用的根目录：`extensions/` 放扩展文件，`backups/<产品>/` 放安装器的备份。

0.4.0 之前目录是同一基础目录下的 `agent-session-launcher/clients/`。新目录不存在时，
`defaultExtensionsDirectory()` 仍返回旧目录；新目录一旦存在，只读取新目录。组件
不会移动你的文件，迁移时自己创建 `agent-clients/extensions/` 并把文件移过去即可。

一个客户端一个文件，**文件名就是客户端 ID**：`acme-agent.json` 定义 `acme-agent`。
ID 由小写字母、数字和连字符组成，最长 64 个字符。只读取该目录下的 `.json`
文件；以 `.` 开头的文件和子目录会被忽略。

## 写法

命令行 Agent：

```json
{
  "$schema": "https://raw.githubusercontent.com/JevonsCode/agent-session-launcher/main/docs/extension.schema.json",
  "schemaVersion": 1,
  "name": "Acme Agent",
  "aliases": ["Acme Agent CLI"],
  "launch": { "command": ["~/bin/acme-agent", "resume", "{id}"] }
}
```

用深链打开的桌面应用：

```json
{
  "schemaVersion": 1,
  "name": "Acme Desktop",
  "launch": { "uri": "acme://sessions/{id}", "idFormat": "uuid" }
}
```

把内置客户端换成自己的包装命令，文件名用内置 ID，例如 `claude-code.json`：

```json
{ "schemaVersion": 1, "launch": { "command": ["claude-work", "--resume", "{id}"] } }
```

字段与 [宿主配置](configuration.md) 中 `clients.<id>` 的值相同，另需
`schemaVersion: 1`：

| 字段 | 说明 |
| --- | --- |
| `name` | 设置页中显示的名称，默认为 ID。 |
| `aliases` | Agent 上报的来源标签，不区分大小写和标点。新客户端的 ID 自动算一个。 |
| `launch.command` | 程序加固定参数，恰好有一个参数是 `{id}`。程序可以是 PATH 中的程序名，也可以是绝对路径或 `~/` 开头的路径。会在会话工作目录中用 Terminal / iTerm / Windows Terminal 打开。 |
| `launch.uri` | `scheme://host/path?key=value` 模板，`{id}` 必须是完整的路径段或查询值。不接受 `http(s)`、`file` 等协议。 |
| `launch.idFormat` | `safe`（默认）或 `uuid`，深链另有 `claude-desktop`、`cursor-background`。 |
| `preferences` | 只对该客户端生效的终端偏好，例如 `{ "macosTerminal": "iterm" }`。 |
| `enabled` | `false` 时只识别来源，不提供打开。 |

覆盖内置客户端时，打开方式的类型和 `idSource` 不能改变，`idFormat` 只能收紧。
`codex`、`claude-code-unknown` 这类同时覆盖多个产品形态的标签不能配置。

文件还可以写 `install` 段，告诉
[agent-installer](https://github.com/JevonsCode/agent-installer) 把产品接入装在这个
客户端的哪里。两个组件的约定：同一个目录、文件名即客户端 ID、`schemaVersion: 1`；
本组件忽略 `install`，agent-installer 只读 `install`；只有 `install` 的文件不会成为
可打开会话的客户端。

## 检查

写完后可以在终端里检查：

```sh
agent-session-launcher check ~/.config/agent-clients/extensions/acme-agent.json
```

通过时输出该客户端的设置页信息，否则输出原因，例如：

```text
acme-agent.json: $.launch.command: arguments must contain "{id}" exactly once.
```

`check` 只检查这一个文件。与其他文件或宿主配置的冲突会出现在宿主设置页的
客户端列表（协议 `clients` 动作的 `extensionErrors`）中。

## 出错时

- 一个文件出错只会跳过该文件，其他客户端照常工作。
- 两个文件声明了同一个来源标签时，两个都会被跳过，结果不取决于文件名顺序。
- 与内置客户端或宿主配置已使用的来源标签冲突时，跳过该扩展文件。
- 文件大于 16 KiB、目录中超过 64 个文件时，多出的部分不会加载。
- macOS / Linux 上，其他用户可写的文件或目录会被拒绝，和 `~/.ssh` 的规则相同。

宿主在打开设置页、显示“打开会话”按钮和执行打开前都会重新读取目录，修改后
不需要重启。

## 优先级与信任

内置目录 < 本机扩展 < 宿主配置 < 单次请求的终端偏好。宿主设置页里停用某个扩展
客户端或修改它的终端偏好，以宿主为准。

扩展文件可以指定启动的本机程序，信任级别与你自己的 Shell 配置相同。会话请求
只能给出客户端 ID 和会话 ID，不能指定命令、路径或深链；只有在宿主中明确点击后
才会打开。错误信息只包含文件名，不包含完整路径。
