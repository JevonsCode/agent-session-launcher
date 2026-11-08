# Changelog

## 0.5.1

### Fixed

- macOS: Terminal's `do script` and iTerm's `write text` typed the whole
  command, prompt included, into an interactive shell, where a tab in the
  prompt could trigger completion and close a quote. A CLI plan is now
  written to `launch.sh` in a private temporary directory and the terminal
  only types `exec /bin/sh '<file>'`; the script removes itself (or the
  launcher does, when the launch is refused). Applies to resumed sessions too.

### Tests

- macOS/Linux CI runs the script the terminal would run and checks every
  argument (tabs, carriage returns, `$(…)`, CJK) and that it removed itself.
- Windows: a real round trip through PowerShell, `wsl.exe` and bash, skipped
  without a WSL distribution.

## 0.5.0

### Added

- New sessions: `inspectNew` / `openNew` (protocol `inspect-new` /
  `open-new`) open a new session in a client, optionally with one prompt that
  the client receives as plain data: one argument or one percent-encoded URI
  value, never shell text. `clients` reports each client's way as
  `newSession: { kind, prompt: 'prefill' | 'send' | null, openSupported }`.
  Hosts and extensions describe their own with `newSession`
  (docs/configuration.md).
- 26 built-in clients with a verified new-session way, each with its official
  source in docs/clients.md: Claude Code (CLI, VS Code, Desktop's Code tab and
  chat), Codex (app and CLI), Cursor (IDE and CLI), GitHub Copilot (CLI and
  VS Code), Gemini CLI, Antigravity CLI, OpenCode CLI, Kiro CLI, Qwen Code,
  Qoder (IDE and CLI), Junie CLI, Kilo CLI, Cline, Devin CLI, Pi, Zed, Goose
  Desktop, Aider and Amp, with resume entries for several of them.
- Prompts are 1–2000 characters; control characters other than tabs and line
  breaks are refused, and a CLI prompt may not begin with `-`
  (`invalid_prompt`). A prompt for a way that takes none is
  `unsupported_prompt`.
- Windows: `environment: "wsl"` runs a CLI that lives in WSL through
  `wsl.exe --cd … --exec bash -lic`.
- Windows: a new CLI session runs one `-EncodedCommand` PowerShell script, so
  the prompt never passes through Windows Terminal's or PowerShell's argument
  parsing; `.cmd` shims get Rust's batch-file quoting through `cmd.exe` (line
  breaks become spaces there). The client starts without the variables a
  parent Agent session sets for its children: an inherited
  `CLAUDE_CODE_CHILD_SESSION` turned off transcript saving in Claude Code.
- Linux: CLI plans open in the first terminal found (`x-terminal-emulator`,
  then GNOME Terminal, Konsole, Xfce Terminal, kitty, Alacritty, WezTerm, foot,
  xterm); `plan.opener` names it.

### Changed

- Windows: URIs open through `ShellExecute` (PowerShell,
  `System.Diagnostics.Process`) instead of `explorer.exe`, which opened the
  Documents folder for `codex://new?…` and `cursor://…/prompt?…` links on
  Windows 11. A scheme without a handler is now `launch_failed`.

## 0.4.0

### Breaking

- The shared extensions directory moved to the neutral `agent-clients` root
  that agent-installer also uses: `%APPDATA%\agent-clients\extensions` on
  Windows, `$XDG_CONFIG_HOME/agent-clients/extensions` when that is an
  absolute path, else `~/.config/agent-clients/extensions` (macOS included,
  as before). The installer keeps its backups in `agent-clients/backups/<product>`.
  - While the new directory does not exist, `defaultExtensionsDirectory()`
    (Dart and Node) returns the 0.3 directory `agent-session-launcher/clients`
    under the same base, so existing files keep working.
  - Files are never moved automatically. To move, create
    `agent-clients/extensions` and move your `.json` files into it; once it
    exists the old directory is no longer read.

### Changed

- Windows: a URI opened through `explorer.exe` is no longer reported as
  `launch_failed` because of its exit code. explorer.exe commonly exits with 1
  even after it handed the URI to the registered app; only a failure to start
  it or a timeout is reported now.
- Windows: when Windows Terminal (`wt.exe`) is not on PATH, a CLI session
  opens in a new console window through Windows PowerShell instead of failing.
  `inspect` reports the choice as `plan.opener` (`windows-terminal` or
  `powershell`); `SessionLauncher` takes a `commandAvailable` lookup for tests.
- Node binding: the spawn, timeout and parse logic is one `runNative` helper
  shaped like the one in agent-installer's binding. Every failure rejects
  asynchronously with an `Error` carrying `code`; `timeoutMs` (default 8000,
  at most 60000) and `unknown_outcome` (never retried automatically) are
  documented in the README and `index.d.ts`.
- `docs/extension.schema.json`: an `install.afterInstall` step may be
  `{ "code", "message" }` with a stable code (`restart_client`,
  `new_session`, `reload_config`, `trust_hooks`, `other`) besides plain
  text, matching agent-installer 0.2. The launcher still ignores `install`.
