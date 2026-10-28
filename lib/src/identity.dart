/// Maps an explicit source to an identity without guessing ambiguous surfaces.
/// Only the non-secret Claude entrypoint signal may refine a Claude source.
String classifyAgentSource(String source, {String? claudeEntrypoint}) {
  final String normalized = source
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if ((normalized.isEmpty ||
          normalized == 'claude' ||
          normalized == 'claude-code') &&
      claudeEntrypoint?.trim().toLowerCase() == 'claude-desktop') {
    return 'claude-desktop';
  }
  return switch (normalized) {
    'codex' => 'codex',
    'codex-cli' || 'codex-terminal' => 'codex-cli',
    'codex-desktop' || 'codex-app' => 'codex-desktop',
    'claude-code' => 'claude-code-unknown',
    'claude-code-cli' => 'claude-code',
    'claude-desktop' || 'claude-code-desktop' => 'claude-desktop',
    'opencode' || 'open-code' => 'opencode',
    'opencode-cli' || 'open-code-cli' || 'opencode-terminal' => 'opencode-cli',
    'opencode-desktop' || 'open-code-desktop' => 'opencode-desktop',
    'antigravity' => 'antigravity',
    'antigravity-cli' || 'agy' => 'antigravity-cli',
    'antigravity-ide' => 'antigravity-ide',
    'antigravity-app' || 'antigravity-desktop' => 'antigravity-app',
    'copilot' || 'github-copilot' => 'copilot',
    'copilot-cli' || 'github-copilot-cli' => 'copilot-cli',
    'copilot-ide' || 'github-copilot-vs-code' => 'copilot-ide',
    'pi' || 'pi-coding-agent' => 'pi',
    'grok-build' || 'grok-build-cli' => 'grok-build',
    'gemini-cli' => 'gemini-cli',
    'kiro-cli' => 'kiro-cli',
    'cursor' => 'cursor',
    'windsurf' => 'windsurf',
    _ => 'unknown',
  };
}
