# Agent Session Launcher

English | [简体中文](README.zh.md)

A local Agent session launcher for reuse by Flutter/Dart applications and
Node.js hosts, with a Dart API and a one-shot JSON protocol for Node.js and
other hosts. It takes a **session target whose origin the host has already
verified**, and produces a fixed deep link or CLI arguments; it only tries to
ask the operating system to open the session when `open` is explicitly
requested. It does not save sessions, run models, send messages to an Agent,
or expose an HTTP service. Background Agent execution is out of scope.

## Supported clients

| Specific client | Target | Method |
| --- | --- | --- |
| `claude-desktop` | Desktop's `hostSessionId` | `claude://code/continue` |
| `codex-desktop` | full UUID | `codex://threads/` |
| `cursor` | `bc-` background Agent ID | Cursor deep link |
| `claude-code`, `gemini-cli`, `copilot-cli`, `grok-build` | session ID and working directory | each client's own CLI resume command |
| `pi`, `codex-cli` | full UUID and working directory | each client's own CLI resume command |
| `opencode-cli`, `antigravity-cli`, `kiro-cli` | session ID and working directory | each client's own CLI resume command |

`codex`, `claude-code-unknown`, `opencode`, `opencode-desktop`, the generic
`antigravity`, the Antigravity App/IDE, generic Copilot, and Windsurf are
never guessed as a CLI. When classifying, `Claude Code` alone is not enough
to tell Desktop and CLI apart: it is classified as `claude-desktop` when
there is an explicit Desktop entrypoint, and as CLI when there is an explicit
`Claude Code CLI` source. Some OpenCode events also don't distinguish Desktop
from CLI; the host must obtain a reliable source first.

On macOS, CLI sessions open in Terminal or iTerm; on Windows, in Windows
Terminal. Linux can produce a CLI plan, but interactive terminal opening is
not yet implemented there. The URI path asks the system to open it, with its
own implementation on macOS, Windows, and Linux; these capabilities still
depend on the client and the corresponding system component actually being
installed.

The Claude Desktop deep link comes from observing local behavior; it is not
a publicly stable contract this project can guarantee. The component does
not recognize, store, or switch logged-in accounts — opening a session uses
the target client's current login state and configuration. `inspect`'s
`openSupported` only means the current platform has an implementation; it
does not verify that the app, account, or session exists.

## Download

Each release on [Releases](https://github.com/JevonsCode/agent-session-launcher/releases) provides a compiled executable; Dart does not need to be installed:

| Platform | File |
| --- | --- |
| macOS (Apple silicon) | `agent-session-launcher-macos-arm64` |
| macOS (Intel) | `agent-session-launcher-macos-x64` |
| Linux x64 / arm64 | `agent-session-launcher-linux-x64`, `agent-session-launcher-linux-arm64` |
| Windows x64 | `agent-session-launcher-windows-x64.exe` |

Verify with the `SHA256SUMS` file in the same directory. On macOS, a file
downloaded through a browser needs `xattr -d com.apple.quarantine <file>`
followed by `chmod +x`; a file downloaded with `curl` only needs `chmod +x`.
A Node host just needs to pass the downloaded file's path as `executable` to
the binding.

## Build and usage

Requires Dart SDK 3.10 or later. Full integration steps for hosts such as
DingDong and FULI, mapped to the fields of an existing setup, are in the
[integration guide](docs/integration.md).

A Flutter/Dart application calls it in-process via a Git dependency (the
package is not yet published to pub.dev):

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
    hostConfig: configText, // optional
    extensionsDirectory: defaultExtensionsDirectory(), // user's local extensions
  ),
);
final client = launcher.classify('Claude Code', claudeEntrypoint: 'claude-desktop');
final target = SessionTarget(
  client: client,
  hostSessionId: 'local_example', // example: use the ID the host actually stored
);
final plan = launcher.inspect(target); // does not launch anything
// Once the user explicitly chooses to open it, the host calls launcher.open(target).
```

A Node.js host first builds an executable for the target platform, then uses
the dependency-free binding:

```sh
dart pub get
mkdir -p build
dart compile exe bin/agent_session_launcher.dart -o build/agent-session-launcher
```

```javascript
import { createLauncher, defaultExtensionsDirectory } from './bindings/node/index.mjs';

const launcher = createLauncher({
  executable: '/absolute/path/to/agent-session-launcher',
  configPath: '/absolute/path/to/launcher.json', // optional
  extensionsDir: defaultExtensionsDirectory(), // optional, user's local extensions
});
await launcher.classify('Claude Code', { claudeEntrypoint: 'claude-desktop' });
// 'claude-desktop'; rejects with an Error carrying a code on failure
```

The executable reads one JSON object from stdin and exits after printing one
JSON object; the `classify`, `clients`, `inspect`, `open` actions and error
codes are in the [protocol reference](docs/protocol.md). A build must match
the host's OS and CPU architecture — a macOS build cannot be distributed as
a Windows/Linux binary. The repository does not currently ship precompiled
release packages.

## Configuration

The built-in clients are just a default configuration
([`lib/src/catalog.dart`](lib/src/catalog.dart)). A host writes a local
trusted JSON file in the same format, merged by client ID after the local
extensions: it can disable a client, rename it, append source tags, replace
how it opens, add a client, and set terminal preferences globally or per
client.

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

A user's local private Agent (an internal CLI, a wrapper script, a private
desktop app) needs no host configuration change: drop a `<client-id>.json`
file into `~/.config/agent-session-launcher/clients/`
(`%APPDATA%\agent-session-launcher\clients\` on Windows), and every
integrated host will recognize it. An error in one file only skips that
file; check it yourself with `agent-session-launcher check <file>` — see
[local extensions](docs/extensions.md).

```json
{
  "schemaVersion": 1,
  "name": "Acme Agent",
  "aliases": ["Acme Agent CLI"],
  "launch": { "command": ["~/bin/acme-agent", "resume", "{id}"] }
}
```

Configuration and extensions can specify which local program to launch, but
only from the host's own local configuration or the user's own files — a
session request cannot specify a config path, command, or deep link. The
configuration is validated as a whole; on error it returns
`invalid_configuration` and the JSON path of the error, and never takes
partial effect. Fields, merge rules, and the constraints that cannot be
relaxed are in the [host configuration](docs/configuration.md) doc; editors
can use the [JSON Schema](docs/config.schema.json).

## Installing into an Agent

Installing a product's integration (MCP, hooks, instructions, skills) into a
local Agent is handled by the separate
[agent-installer](https://github.com/JevonsCode/agent-installer) repository.
The two share the local extensions directory: it reads the `install` section
of an extension file, this component ignores that section, and a file whose
only field is `install` never becomes a client this component can open a
session for.

## Host integration boundaries

- The host is responsible for verifying the source and session ownership
  before passing in an explicit `client`; this component never scans another
  product's data to guess an account or migrate history.
- Only a trusted local interaction may trigger `open`. If a web application
  needs this, its own local service must verify the user's action and
  request permission — this project exposes no open interface a web page can
  call directly.
- A JSON request cannot carry an executable path, command, arbitrary URL,
  environment variable, or credential. Commands and arguments are produced
  by the component's own fixed mapping. The executable path in the Node
  binding is the host's own local configuration.
- `launch_requested` only means the system accepted the launch request; it
  does not mean the client finished logging in or resuming. A timeout can
  leave an uncertain result, and the host must not automatically retry a
  session that may already be open.
- FULI's background Agent wake-up, authorization, messaging, and result
  handling are a separate capability; this component does not replace them.
  FULI's OpenCode lifecycle plugin is also not equivalent to "opening the
  original session" — the two hosts each need to complete their own wiring
  and verification. This repository does not modify any existing DingDong or
  FULI configuration.

## Verification

```sh
dart test
dart analyze
AGENT_SESSION_LAUNCHER_BIN="$PWD/build/agent-session-launcher" node --test test/node_binding_test.mjs
```

The optional real Pi test needs `PI_EXECUTABLE` pointing at a local Pi; tests
use a temp directory, offline RPC, and synthetic sessions, and never send a
model request. Current coverage is macOS, Node.js, and a local Pi; the
Windows path and invocation are only covered by automated simulation and
have not yet been verified on real Windows hardware.

Client references: [OpenCode CLI](https://opencode.ai/docs/cli/),
[Antigravity CLI](https://antigravity.google/docs/cli/commands/resume),
[GitHub Copilot CLI](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference),
[Grok Build CLI](https://docs.x.ai/build/cli/reference).
