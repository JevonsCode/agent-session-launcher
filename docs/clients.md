# Agent clients: new sessions and resume

How each mainstream Agent client opens a **new session** (optionally with a
prompt) or **resumes** one by ID, checked on 2026-11-08. Every row that the
launcher ships cites an official source: the vendor's documentation,
changelog or its own open-source code. Mechanisms first seen on X, Reddit,
Hacker News or third-party blogs were looked up there and shipped only when an
official source confirmed them; the rest are listed under
[Not shipped](#not-shipped).

- **prefill**: the prompt waits in the composer; the person sends it.
- **send**: the client submits the prompt as the first message and stays
  interactive.
- **Live** marks what was opened on a real Windows 11 machine with this
  launcher (0.5.0): a new window, the prompt intact, including quotes, `%`, `&`
  and Chinese text.
- **MCP prompts in `/`**: whether the client lists an MCP server's prompts
  (`prompts/list`) as slash commands. Hosts such as FULI rely on this for
  picker menus.

## Shipped in the catalog

| Launcher ID | New session | Prompt | Folder | Resume by ID | MCP prompts in `/` | Source | Live |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `claude-code` | `claude <prompt>` | send | working directory | `claude --resume <id>` | yes: `/mcp__server__prompt` | [CLI reference](https://code.claude.com/docs/en/cli-reference), [MCP prompts](https://code.claude.com/docs/en/mcp) | ✅ Windows Terminal, sent |
| `claude-code-vscode` | `vscode://anthropic.claude-code/open?prompt=` | prefill | the folder open in VS Code | `…/open?session=<id>` | not documented for this surface | [VS Code: launch a tab](https://code.claude.com/docs/en/vs-code#launch-a-vs-code-tab-from-other-tools) | — |
| `claude-desktop` (Code tab) | `claude://code/new?q=` | prefill | `folder=` exists, always confirmed; not used | `claude://code/continue?session=` (observed, not documented) | not documented | [Open Claude Desktop with a link](https://support.claude.com/en/articles/14729294) | not run (it is the host app) |
| `claude-chat` | `claude://claude.ai/new?q=` (cut at about 14,000 characters) | prefill | — | `claude://claude.ai/chat/<uuid>` | not documented | [Open Claude Desktop with a link](https://support.claude.com/en/articles/14729294) | not run |
| `codex-desktop` | `codex://new?prompt=` | prefill | `path=` exists; not used | `codex://threads/<uuid>` | no ([openai/codex#5059](https://github.com/openai/codex/issues/5059) open) | [Codex app commands](https://learn.chatgpt.com/docs/reference/commands) | ✅ composer filled |
| `codex-cli` | `codex <prompt>` | send | working directory (`-C`) | `codex resume <uuid>` | no | [CLI reference](https://learn.chatgpt.com/docs/developer-commands?surface=cli), [`tui/src/cli.rs`](https://github.com/openai/codex/blob/main/codex-rs/tui/src/cli.rs) | ✅ npm `.cmd` shim, sent |
| `cursor` | `cursor://anysphere.cursor-deeplink/prompt?text=` (10,000 characters) | prefill, after a confirm dialog | — | background agents only (`…/background-agent?bcId=`) | "Prompts: supported"; `/` listing not documented | [Deeplinks](https://cursor.com/docs/integrations/deeplinks) | ✅ "Create chat with prompt" dialog |
| `cursor-cli` | `agent <prompt>` | send ("start with initial prompt") | working directory (`--workspace`) | `agent --resume <id>` | not documented | [CLI parameters](https://cursor.com/docs/cli/reference/parameters) | opened; asks to trust a new folder first |
| `copilot-cli` | `copilot -i <prompt>` | send | working directory | `copilot --resume <id>` | not documented | [Copilot CLI reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference) | not installed |
| `copilot-ide` | `vscode://github.copilot-chat/chat?prompt=` | prefill | the folder open in VS Code | — | yes: `/<server>.<prompt>` | [Copilot features](https://code.visualstudio.com/docs/copilot/reference/copilot-vscode-features), [`chatSetupContributions.ts`](https://github.com/microsoft/vscode/blob/main/src/vs/workbench/contrib/chat/browser/chatSetup/chatSetupContributions.ts), [MCP](https://code.visualstudio.com/docs/copilot/customization/mcp-servers) | ✅ VS Code asks to let Copilot Chat open the link |
| `gemini-cli` | `gemini -i <prompt>` | send | working directory | `gemini --resume <uuid>` (per project folder) | yes | [CLI reference](https://geminicli.com/docs/cli/cli-reference/), [MCP prompts as slash commands](https://geminicli.com/docs/tools/mcp-server/#mcp-prompts-as-slash-commands) | not installed |
| `antigravity-cli` | `agy -i <prompt>` | send | working directory | `agy --conversation <id>` | not documented | [CLI reference](https://antigravity.google/docs/cli/reference/), [resume](https://antigravity.google/docs/cli/commands/resume) | opened; asks to trust a new folder first |
| `opencode-cli` | `opencode --prompt <prompt>` | send | working directory (or positional) | `opencode --session <id>` | yes (source) | [`commands.ts`](https://github.com/anomalyco/opencode/blob/dev/packages/cli/src/commands/commands.ts), [`home.tsx`](https://github.com/anomalyco/opencode/blob/dev/packages/tui/src/routes/home.tsx), `opencode --help` (2.2.5) | ✅ in WSL, sent |
| `kiro-cli` | `kiro-cli chat` | none (see below) | working directory | `kiro-cli chat --resume-id <id>` | through `#`, not `/` | [Session management](https://kiro.dev/docs/cli/chat/session-management/), [MCP](https://kiro.dev/docs/mcp/) | not installed |
| `qwen-code` | `qwen -i <prompt>` | send | working directory | `qwen --resume <id>` | yes | [`top-level-options.ts`](https://github.com/QwenLM/qwen-code/blob/main/packages/cli/src/config/top-level-options.ts), [`McpPromptLoader.ts`](https://github.com/QwenLM/qwen-code/blob/main/packages/cli/src/services/McpPromptLoader.ts) | not installed |
| `qoder-cli` | `qoder -i <prompt>` | send | working directory (`-w`) | `qoder --resume <id>` | not documented | [Qoder CLI reference](https://docs.qoder.com/cli/cli-reference) | not installed |
| `qoder` (IDE) | `qoder://aicoding.aicoding-deeplink/chat?text=&mode=agent&isNewChat=true` | prefill, after a confirm dialog | — | — | not documented | [Qoder deeplinks](https://docs.qoder.com/user-guide/deeplink) | not installed |
| `junie-cli` | `junie --prompt <prompt>` | send | working directory (`--project`) | `junie --resume --session-id <id>` (not in the catalog) | not documented | [Junie CLI parameters](https://junie.jetbrains.com/docs/parameters.html) | not installed |
| `kilo-cli` | `kilo --prompt <prompt>` | send | working directory (or positional) | `kilo --session <id>` | yes (source) | [`tui.ts`](https://github.com/Kilo-Org/kilocode/blob/main/packages/opencode/src/cli/cmd/tui.ts), [`home.tsx`](https://github.com/Kilo-Org/kilocode/blob/main/packages/tui/src/routes/home.tsx) | not installed |
| `cline` (VS Code) | `vscode://saoudrizwan.claude-dev/task?prompt=` | send (starts a task) | the folder open in VS Code | — | not documented | [`SharedUriHandler.ts`](https://github.com/cline/cline/blob/main/apps/vscode/src/services/uri/SharedUriHandler.ts) | not installed |
| `devin-cli` (Windsurf's successor) | `devin -- <prompt>` | send | working directory | `devin --resume <id>` | not documented | [Devin CLI commands](https://docs.devin.ai/cli/reference/commands.md) | not installed |
| `pi` | `pi <prompt>` | send ("initial prompt") | working directory | `pi --session <id>` | not documented | [`cli.md`](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/cli.md) | not installed |
| `zed` | `zed://agent?prompt=` | prefill (Zed shows a warning) | the active Zed window | — | yes (source) | [`open_listener.rs`](https://github.com/zed-industries/zed/blob/main/crates/zed/src/zed/open_listener.rs), [MCP](https://github.com/zed-industries/zed/blob/main/docs/src/ai/mcp.md) | not installed |
| `goose-desktop` | `goose://new-session?prompt=` | prefill | the last used folder | `goose://resume/<id>` | not found | [`main.ts`](https://github.com/block/goose/blob/main/ui/desktop/src/main.ts) | not installed |
| `aider` | `aider` | none: `--message` answers once and exits | working directory | none (chat history per folder) | no MCP | [Options](https://aider.chat/docs/config/options.html), [`main.py`](https://github.com/Aider-AI/aider/blob/main/aider/main.py) | not installed |
| `amp` | `amp` | none: a first message only through stdin | working directory | `amp threads continue <T-id>` | not documented | [Amp CLI](https://ampcode.com/docs/cli), [threads](https://ampcode.com/docs/threads) | not installed |

Notes:

- **Claude Code CLI** also has an official deep link,
  `claude-cli://open?q=<prompt>&cwd=<abs path>` (5,000 characters, prefill,
  opens the person's terminal); its handler registers only after the first
  interactive `claude` session
  ([deep links](https://code.claude.com/docs/en/deep-links)). The catalog's
  `claude-code` uses the CLI so the session starts in a known folder.
- **Kiro CLI**: the 2.x [command reference](https://kiro.dev/docs/reference/cli-commands/)
  documents a first question as a positional argument; the 3.x pages do not,
  so the catalog opens a new session without a prompt.
- **Gemini CLI** was replaced by Antigravity CLI for unpaid and Google One
  users on 2026-06-18 (banner on its CLI reference); paid and API-key users
  keep it.
- **OpenCode**: `--prompt` was checked in the `dev` source and in
  `opencode --help` of 2.2.5. The desktop app registers `opencode://`, but the
  only route in its source is a sign-in callback.
- **Trust prompts**: Cursor CLI and Antigravity ask whether to trust a folder
  they have not seen; the prompt waits behind that question.
- **Windows URIs** open through `ShellExecute`. `explorer.exe <uri>` opened the
  Documents folder instead of Codex or Cursor for these query links on
  Windows 11, so the launcher no longer uses it.

## Not shipped

| Client | Why |
| --- | --- |
| Windsurf (now "Devin Desktop") | No documented `windsurf://` chat link or `windsurf chat` command; only third-party posts. Its terminal route is `devin-cli`. |
| Antigravity IDE / App | `antigravity://` appears only in a blog; the official getting-started page documents no URL scheme. |
| Kiro IDE | `kiro://` is documented only for MCP install links. |
| Trae IDE | Only an MCP import link (`trae://trae.ai-ide/mcp-import`); `trae://file/…` is third-party. Trae Agent CLI has no interactive first prompt. |
| JetBrains AI Assistant / Junie plugin | No `jetbrains://` chat link documented. The Junie CLI is shipped. |
| Codex IDE extension | No URI handler for a new thread is documented. |
| Roo Code | Archived in 2026-05; its URI handler is for sign-in only. |
| Kilo Code extension | Its URI handler opens cloud sessions only. |
| Warp | Its URI scheme cannot run or prefill an agent prompt (stated in its docs); the `warp` agent CLI has no first-prompt flag. |
| Crush | No first-prompt flag for its TUI; `crush run` is one-shot. |
| Continue (`cn`), Auggie, Factory Droid, Kimi Code | Prompt handling (prefill or send) or resume by ID not confirmed in their docs; can be added as extensions. |
| Claude Desktop resume by URL | `claude://code/{id}` and `claude://resume?session=` come from a community issue only. The existing `claude://code/continue` resume was observed in the app, not documented. |
| GitHub Copilot app (`ghapp://session/new`) | Documented, but it opens a GitHub repository, not a local folder; no local client to classify yet. |
| `vscode://agents/new` | Found in VS Code source only, marked preview. |

## Adding one

A client missing here can be described in a host configuration or an
extension file with the same `newSession` shape (see
[configuration.md](configuration.md)). Record its official source in this
table when adding it to the built-in catalog.
