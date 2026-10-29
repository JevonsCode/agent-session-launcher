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

`open` performs an explicit interactive launch with the same validated target.
Optional `preferences` override the configured terminal preferences.
`launch_requested` confirms only OS-level launch acceptance. The caller must
authorize the action and must not expose it as an unauthenticated web endpoint.

Error codes include `invalid_request`, `invalid_preferences`,
`invalid_configuration`, `invalid_target`, `unsupported_client`,
`client_disabled`, `unsupported_target`, `unsupported_platform`,
`workspace_missing`, `launch_failed`, `launch_timeout`, and `internal_error`.
The Node binding can additionally throw `invalid_executable`, `invalid_timeout`,
`unavailable`, `invalid_response`, or `unknown_outcome`. A timeout may occur
after an OS launch was requested; do not automatically repeat it.

The native process optionally accepts `--config /absolute/path/to/config.json`
and `--extensions /absolute/path/to/clients` from its trusted host and rereads
both on every call. Paths and client definitions are not request fields. An
invalid host configuration fails every request with `invalid_configuration`
and a message naming the JSON location; an invalid extension file only skips
that file. See [configuration.md](configuration.md) and
[extensions.md](extensions.md).

`agent-session-launcher check <client-id>.json` is a separate human-facing
command that validates one extension file and exits nonzero on failure.
