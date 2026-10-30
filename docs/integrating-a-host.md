# Integrating a host

A host is any application that records Agent sessions and offers to reopen
them. It does three things:

1. **Provide configuration**: pass no configuration to use the built-in
   defaults, or turn the host's own settings into a
   [host configuration](configuration.md). Also pass the user's
   [local extensions](extensions.md) directory, usually
   `defaultExtensionsDirectory()`.
2. **Identify the source**: call `classify` on the source label from a hook or
   event, and store the resulting client ID with the session ID and working
   directory.
3. **Open the session**: call `inspect` before showing an "Open session"
   control; call `open` only after the person explicitly asks for it.

A settings screen can list every specific client with `clients`: name,
enabled state, opening kind, which ID it needs, whether it needs a working
directory, and whether this platform can open it.

The host stays responsible for storing sessions and checking who owns them,
authorizing the action, host-specific pre-checks, and any fallback that only
opens a working directory without resuming a session.

## Local extensions in a settings screen

- Mark clients whose `origin` is `extension` as local extensions, and built-in
  clients with an `extensionFile` as customized.
- When `extensionErrors` is not empty, list each file name and reason.
- Offer "Open extensions folder" (creating it when missing) and a link to the
  [extension guide](extensions.md).
- Reread before showing the settings screen, before rendering an "Open
  session" control and before `open`; there is no need to watch files.

## Dart / Flutter host

In-process, no native executable needed. Pin the dependency to a commit or tag:

```yaml
dependencies:
  agent_session_launcher:
    git:
      url: https://github.com/JevonsCode/agent-session-launcher.git
      ref: <commit-or-tag>
```

```dart
import 'package:agent_session_launcher/agent_session_launcher.dart';

final LauncherConfig config = LauncherConfig.load(
  hostConfig: await configFile.exists() ? await configFile.readAsString() : null,
  extensionsDirectory: defaultExtensionsDirectory(),
);
final SessionLauncher launcher = SessionLauncher(config: config);

final String client = launcher.classify(source, claudeEntrypoint: entrypoint);
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
// After the person clicks:
await launcher.open(target);
```

## Node.js host

The binding is a dependency-free ES module (not yet on npm): copy
`bindings/node/` or add the repository as a submodule. Ship a native
executable built for each OS and CPU (see the README's download table).

```javascript
import { createLauncher, defaultExtensionsDirectory } from './vendor/agent-session-launcher/index.mjs';

const launcher = createLauncher({
  executable: '/absolute/path/to/agent-session-launcher',
  configPath: '/absolute/path/to/launcher.json', // optional, kept by the host
  extensionsDir: defaultExtensionsDirectory(),
});

const client = await launcher.classify('Claude Code', { claudeEntrypoint: 'claude-desktop' });
const { clients, extensionErrors } = await launcher.clients();
const { plan, openSupported } = await launcher.inspect(target);
await launcher.open(target); // only after an explicit user action
```

Every failure rejects with an `Error` whose `code` matches the
[protocol](protocol.md). `unknown_outcome` means no answer arrived within
`timeoutMs` (default 8000 ms); the session may already be open, so never
retry automatically.

## Mapping an existing launcher setting

A host that already has its own "open with" settings can generate the host
configuration whenever those settings are saved, instead of reimplementing
the launch rules. The usual mapping is:

| Host setting (example) | Host configuration |
| --- | --- |
| a default terminal choice | `preferences.macosTerminal`, `preferences.itermOpenMode` |
| a per-client terminal choice | `clients.<id>.preferences.*` |
| a per-client on/off switch | `clients.<id>.enabled` |
| a per-client display name | `clients.<id>.name` |
| a per-client deep-link template | `clients.<id>.launch.uri` (`{id}` must be a whole path segment or query value; web, file and script schemes are refused) |
| a per-client resume command | `clients.<id>.launch.command` |
| "any ID" | `idFormat: "safe"` |
| a host-defined client | a new client ID, e.g. `example-desktop` |

Map the host's own client names to this component's IDs once (for example a
host's `claude` becomes `claude-code` or `claude-desktop`, decided by
`classify`). Avoid substring checks such as "contains claude": they cannot
tell Claude Desktop from Claude Code CLI.

## Acceptance

Verify each host separately: the source is classified correctly, the
`inspect` plan is what you expect, and a real click opens the right session
in the right client. `launch_requested` only means the operating system
accepted the request, not that the client signed in or resumed.
