/// Built-in clients, written in the same shape as a host configuration's
/// `clients` object. Only this catalog may mark an identity `ambiguous`: such a
/// label is known to cover several surfaces, so it can be classified but never
/// opened or configured. Verify upstream flags when a client changes.
const Map<String, Object?> builtinClients = <String, Object?>{
  'claude-code': <String, Object?>{
    'name': 'Claude Code CLI',
    'aliases': <String>['Claude Code CLI'],
    'launch': <String, Object?>{
      'command': <String>['claude', '--resume', '{id}'],
    },
  },
  'claude-desktop': <String, Object?>{
    'name': 'Claude Desktop',
    'aliases': <String>['Claude Desktop', 'Claude Code Desktop'],
    'launch': <String, Object?>{
      'uri': 'claude://code/continue?session={id}',
      'idSource': 'hostSessionId',
      'idFormat': 'claude-desktop',
    },
  },
  'claude-code-unknown': <String, Object?>{
    'name': 'Claude Code',
    'aliases': <String>['Claude Code'],
    'ambiguous': true,
  },
  'codex-desktop': <String, Object?>{
    'name': 'Codex Desktop',
    'aliases': <String>['Codex Desktop', 'Codex App'],
    'launch': <String, Object?>{
      'uri': 'codex://threads/{id}',
      'idFormat': 'uuid',
    },
  },
  'codex-cli': <String, Object?>{
    'name': 'Codex CLI',
    'aliases': <String>['Codex CLI', 'Codex Terminal'],
    'launch': <String, Object?>{
      'command': <String>['codex', 'resume', '{id}'],
      'idFormat': 'uuid',
    },
  },
  'codex': <String, Object?>{
    'name': 'Codex',
    'aliases': <String>['Codex'],
    'ambiguous': true,
  },
  'cursor': <String, Object?>{
    'name': 'Cursor',
    'aliases': <String>['Cursor'],
    'launch': <String, Object?>{
      'uri': 'cursor://anysphere.cursor-deeplink/background-agent?bcId={id}',
      'idFormat': 'cursor-background',
    },
  },
  'pi': <String, Object?>{
    'name': 'Pi',
    'aliases': <String>['Pi', 'Pi Coding Agent'],
    'launch': <String, Object?>{
      'command': <String>['pi', '--session', '{id}'],
      'idFormat': 'uuid',
    },
  },
  'opencode-cli': <String, Object?>{
    'name': 'OpenCode CLI',
    'aliases': <String>['OpenCode CLI', 'Open Code CLI', 'OpenCode Terminal'],
    'launch': <String, Object?>{
      'command': <String>['opencode', '--session', '{id}'],
    },
  },
  'opencode-desktop': <String, Object?>{
    'name': 'OpenCode Desktop',
    'aliases': <String>['OpenCode Desktop', 'Open Code Desktop'],
  },
  'opencode': <String, Object?>{
    'name': 'OpenCode',
    'aliases': <String>['OpenCode', 'Open Code'],
    'ambiguous': true,
  },
  'antigravity-cli': <String, Object?>{
    'name': 'Antigravity CLI',
    'aliases': <String>['Antigravity CLI', 'agy'],
    'launch': <String, Object?>{
      'command': <String>['agy', '--conversation', '{id}'],
    },
  },
  'antigravity-ide': <String, Object?>{
    'name': 'Antigravity IDE',
    'aliases': <String>['Antigravity IDE'],
  },
  'antigravity-app': <String, Object?>{
    'name': 'Antigravity App',
    'aliases': <String>['Antigravity App', 'Antigravity Desktop'],
  },
  'antigravity': <String, Object?>{
    'name': 'Antigravity',
    'aliases': <String>['Antigravity'],
    'ambiguous': true,
  },
  'copilot-cli': <String, Object?>{
    'name': 'GitHub Copilot CLI',
    'aliases': <String>['Copilot CLI', 'GitHub Copilot CLI'],
    'launch': <String, Object?>{
      'command': <String>['copilot', '--resume', '{id}'],
    },
  },
  'copilot-ide': <String, Object?>{
    'name': 'GitHub Copilot IDE',
    'aliases': <String>['Copilot IDE', 'GitHub Copilot VS Code'],
  },
  'copilot': <String, Object?>{
    'name': 'GitHub Copilot',
    'aliases': <String>['Copilot', 'GitHub Copilot'],
    'ambiguous': true,
  },
  'grok-build': <String, Object?>{
    'name': 'Grok Build',
    'aliases': <String>['Grok Build', 'Grok Build CLI'],
    'launch': <String, Object?>{
      'command': <String>['grok', '--resume', '{id}'],
    },
  },
  'gemini-cli': <String, Object?>{
    'name': 'Gemini CLI',
    'aliases': <String>['Gemini CLI'],
    'launch': <String, Object?>{
      'command': <String>['gemini', '--resume', '{id}'],
    },
  },
  'kiro-cli': <String, Object?>{
    'name': 'Kiro CLI',
    'aliases': <String>['Kiro CLI'],
    'launch': <String, Object?>{
      'command': <String>['kiro-cli', 'chat', '--resume-id', '{id}'],
    },
  },
  'windsurf': <String, Object?>{
    'name': 'Windsurf',
    'aliases': <String>['Windsurf'],
  },
  'unknown': <String, Object?>{'name': 'Unknown', 'ambiguous': true},
};
