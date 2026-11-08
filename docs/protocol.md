# JSON protocol v1

The executable reads one UTF-8 JSON request from stdin (at most 64 KiB) and
returns one JSON response on stdout. `ok: false` exits nonzero. No diagnostic
includes the request or local file paths. See
[request.schema.json](request.schema.json) for request fields.

`classify` accepts a source label and, optionally, the non-secret Claude
entrypoint signal. It returns a conservative client identity; it does not prove
which account owns a conversation.

`clients` returns every specific client after configuration: `id`, `name`,
`enabled`, `builtin`, `origin` (`builtin`, `extension` or `host`),
`extensionFile` (the user extension file that defines or customizes it, when
any), `kind` (`cli`, `uri`, or `null` when no opening method is known),
`idSource`, `idFormat`, `requiresWorkspace` and `openSupported`. Ambiguous
labels such as `codex` or `claude-code-unknown` are omitted. The response also
has `extensionErrors`: `[{ "file": "acme-agent.json", "message": "..." }]` for
skipped extension files (`file` is absent for a directory problem).

`inspect` checks the structured target and returns `plan` plus `openSupported`.
Plans are fixed executable/argument vectors or allow-listed URI shapes. This is
pure planning: it does not open a client or verify that the target exists.
On Windows a CLI plan also has `opener`: `windows-terminal` when `wt.exe` is
on PATH (`wt.exe -d <workspace> <program> <args>`), otherwise `powershell` (a
new console window started by Windows PowerShell through
`System.Diagnostics.Process` with every value as a single-quoted literal). On
Linux it names the terminal program found, in this order:
`x-terminal-emulator`, `gnome-terminal`, `konsole`, `xfce4-terminal`, `kitty`,
`alacritty`, `wezterm`, `foot`, `xterm`. The terminal runs
`sh -c 'cd -- "$1" && shift && exec "$@"'` with the workspace, program and
arguments as positional parameters.

`open` performs an explicit interactive launch with the same validated target.
Optional `preferences` override the configured terminal preferences.
`launch_requested` confirms only OS-level launch acceptance. The caller must
authorize the action and must not expose it as an unauthenticated web endpoint.

## New sessions

`inspect-new` and `open-new` take
`target: { client, prompt?, workspacePath?, environment? }` and otherwise
behave like `inspect` and `open`. `clients` reports each client's way as
`newSession: { kind, prompt, openSupported }` (`prompt` is `prefill`, `send`,
or `null` when the way takes none), or `newSession: null`. The verified ways
and their sources are in [clients.md](clients.md).

- `prompt` is 1–2000 characters of text; tabs and line breaks are allowed,
  other control characters are not, and a CLI prompt may not begin with `-`
  (the client would read it as an option). It is always one argument or one
  percent-encoded URI query value, never shell text. A plan reports what the
  client does with it as `plan.prompt`. A prompt for a way that takes none is
  `unsupported_prompt`.
- `workspacePath` is where a CLI starts; without it, the home directory.
- `environment: "wsl"` (Windows, CLI only) runs the client inside the default
  WSL distribution: `wsl.exe --cd <workspace or ~> --exec bash -lic '…'
  <program> <args>`, so the person's shell profile puts it on PATH; a `~/`
  program is expanded there.

On Windows a new CLI session runs one PowerShell script passed as
`-EncodedCommand` (in Windows Terminal, or a new console window), so neither
Windows Terminal's `;` splitting nor PowerShell's argument passing ever sees
the prompt. The script finds the program on PATH, builds its command line with
the C runtime's quoting, or with Rust's batch-file quoting for an npm-style
`.cmd` shim run through `cmd.exe` (where line breaks become spaces and `%`
cannot expand a variable), starts it in the console without the variables a
parent Agent session sets (`CLAUDECODE`, `CLAUDE_CODE_CHILD_SESSION`,
`CODEX_THREAD_ID`, …), waits for it, and passes its exit code on. When the
program is missing it says so and waits for Enter. Linux terminals also drop
those variables; macOS Terminal and iTerm start a fresh login shell.

On macOS a CLI plan (new or resumed) is written to `launch.sh` in a new
private temporary directory, every value a single-quoted literal, and Terminal
(`do script`) or iTerm (`write text`) only types `exec /bin/sh '<that file>'`.
Nothing of the prompt is typed into the interactive shell, where a tab would
complete and a line break would submit. The script removes itself before it
starts the client; when the system refuses the launch, the launcher removes it.

## Exit codes and errors

A non-zero exit code from the opener is `launch_failed`. On Windows a URI is
opened by `ShellExecute` through Windows PowerShell
(`System.Diagnostics.Process` with `UseShellExecute`), the same way a click
opens it, so a scheme no app handles fails with `launch_failed`. Version 0.4
used `explorer.exe <uri>`, which opened the Documents folder instead of the
app for `codex://` and `cursor://` links with a query on Windows 11.

Error codes include `invalid_request`, `invalid_preferences`,
`invalid_configuration`, `invalid_target`, `invalid_prompt`,
`unsupported_client`, `unsupported_prompt`, `client_disabled`,
`unsupported_target`, `unsupported_platform`, `workspace_missing`,
`launch_failed`, `launch_timeout`, and `internal_error`.
The Node binding rejects (never throws synchronously) with these codes and
additionally `invalid_executable`, `invalid_timeout`, `unavailable`,
`invalid_response`, or `unknown_outcome`. Its `timeoutMs` defaults to 8000 ms
(at most 60000 ms); when it passes, the process is killed and the call
rejects with `unknown_outcome`. That may happen after an OS launch was
requested, so never repeat it automatically.

The native process optionally accepts `--config /absolute/path/to/config.json`
and `--extensions /absolute/path/to/extensions` from its trusted host and rereads
both on every call. Paths and client definitions are not request fields. An
invalid host configuration fails every request with `invalid_configuration`
and a message naming the JSON location; an invalid extension file only skips
that file. See [configuration.md](configuration.md) and
[extensions.md](extensions.md).

`agent-session-launcher check <client-id>.json` is a separate human-facing
command that validates one extension file and exits nonzero on failure.
