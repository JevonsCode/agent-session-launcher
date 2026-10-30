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
