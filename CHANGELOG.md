# Changelog

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
