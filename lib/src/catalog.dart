/// Built-in clients, written in the same shape as a host configuration's
/// `clients` object. Only this catalog may mark an identity `ambiguous`: such a
/// label is known to cover several surfaces, so it can be classified but never
/// opened or configured. Verify upstream flags when a client changes; the
/// source of every `newSession` entry is in docs/clients.md.
const Map<String, Object?> builtinClients = <String, Object?>{
  'claude-code': <String, Object?>{
    'name': 'Claude Code CLI',
    'aliases': <String>['Claude Code CLI'],
    'launch': <String, Object?>{
      'command': <String>['claude', '--resume', '{id}'],
    },
    'newSession': <String, Object?>{
      'command': <String>['claude'],
      'promptArguments': <String>['{prompt}'],
      'prompt': 'send',
    },
  },
  'claude-code-vscode': <String, Object?>{
    'name': 'Claude Code for VS Code',
    'aliases': <String>['Claude Code VS Code', 'Claude Code for VS Code'],
    'launch': <String, Object?>{
      'uri': 'vscode://anthropic.claude-code/open?session={id}',
    },
    'newSession': <String, Object?>{
      'uri': 'vscode://anthropic.claude-code/open?prompt={prompt}',
      'prompt': 'prefill',
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
    'newSession': <String, Object?>{
      'uri': 'claude://code/new?q={prompt}',
      'prompt': 'prefill',
    },
  },
  'claude-chat': <String, Object?>{
    'name': 'Claude (chat)',
    'aliases': <String>['Claude Chat', 'Claude App'],
    'launch': <String, Object?>{
      'uri': 'claude://claude.ai/chat/{id}',
      'idFormat': 'uuid',
    },
    'newSession': <String, Object?>{
      'uri': 'claude://claude.ai/new?q={prompt}',
      'prompt': 'prefill',
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
    'newSession': <String, Object?>{
      'uri': 'codex://new?prompt={prompt}',
      'prompt': 'prefill',
    },
  },
  'codex-cli': <String, Object?>{
    'name': 'Codex CLI',
    'aliases': <String>['Codex CLI', 'Codex Terminal'],
    'launch': <String, Object?>{
      'command': <String>['codex', 'resume', '{id}'],
      'idFormat': 'uuid',
    },
    'newSession': <String, Object?>{
      'command': <String>['codex'],
      'promptArguments': <String>['{prompt}'],
      'prompt': 'send',
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
    'newSession': <String, Object?>{
      'uri': 'cursor://anysphere.cursor-deeplink/prompt?text={prompt}',
      'prompt': 'prefill',
    },
  },
  'cursor-cli': <String, Object?>{
    'name': 'Cursor CLI',
    'aliases': <String>['Cursor CLI', 'Cursor Agent CLI'],
    'launch': <String, Object?>{
      'command': <String>['agent', '--resume', '{id}'],
    },
    'newSession': <String, Object?>{
      'command': <String>['agent'],
      'promptArguments': <String>['{prompt}'],
      'prompt': 'send',
    },
  },
  'pi': <String, Object?>{
    'name': 'Pi',
    'aliases': <String>['Pi', 'Pi Coding Agent'],
    'launch': <String, Object?>{
      'command': <String>['pi', '--session', '{id}'],
      'idFormat': 'uuid',
    },
    'newSession': <String, Object?>{
      'command': <String>['pi'],
      'promptArguments': <String>['{prompt}'],
      'prompt': 'send',
    },
  },
  'opencode-cli': <String, Object?>{
    'name': 'OpenCode CLI',
    'aliases': <String>['OpenCode CLI', 'Open Code CLI', 'OpenCode Terminal'],
    'launch': <String, Object?>{
      'command': <String>['opencode', '--session', '{id}'],
    },
    'newSession': <String, Object?>{
      'command': <String>['opencode'],
      'promptArguments': <String>['--prompt', '{prompt}'],
      'prompt': 'send',
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
    'newSession': <String, Object?>{
      'command': <String>['agy'],
      'promptArguments': <String>['-i', '{prompt}'],
      'prompt': 'send',
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
    'newSession': <String, Object?>{
      'command': <String>['copilot'],
      'promptArguments': <String>['-i', '{prompt}'],
      'prompt': 'send',
    },
  },
  'copilot-ide': <String, Object?>{
    'name': 'GitHub Copilot IDE',
    'aliases': <String>['Copilot IDE', 'GitHub Copilot VS Code'],
    'newSession': <String, Object?>{
      'uri': 'vscode://github.copilot-chat/chat?prompt={prompt}',
      'prompt': 'prefill',
    },
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
    'newSession': <String, Object?>{
      'command': <String>['gemini'],
      'promptArguments': <String>['-i', '{prompt}'],
      'prompt': 'send',
    },
  },
  'kiro-cli': <String, Object?>{
    'name': 'Kiro CLI',
    'aliases': <String>['Kiro CLI'],
    'launch': <String, Object?>{
      'command': <String>['kiro-cli', 'chat', '--resume-id', '{id}'],
    },
    // The 2.x reference documents a first question as a positional
    // argument; the 3.x pages do not, so a new session takes no prompt.
    'newSession': <String, Object?>{
      'command': <String>['kiro-cli', 'chat'],
    },
  },
  'qwen-code': <String, Object?>{
    'name': 'Qwen Code',
    'aliases': <String>['Qwen Code', 'Qwen Code CLI'],
    'launch': <String, Object?>{
      'command': <String>['qwen', '--resume', '{id}'],
    },
    'newSession': <String, Object?>{
      'command': <String>['qwen'],
      'promptArguments': <String>['-i', '{prompt}'],
      'prompt': 'send',
    },
  },
  'qoder-cli': <String, Object?>{
    'name': 'Qoder CLI',
    'aliases': <String>['Qoder CLI'],
    'launch': <String, Object?>{
      'command': <String>['qoder', '--resume', '{id}'],
    },
    'newSession': <String, Object?>{
      'command': <String>['qoder'],
      'promptArguments': <String>['-i', '{prompt}'],
      'prompt': 'send',
    },
  },
  'qoder': <String, Object?>{
    'name': 'Qoder',
    'aliases': <String>['Qoder IDE'],
    'newSession': <String, Object?>{
      'uri':
          'qoder://aicoding.aicoding-deeplink/chat?text={prompt}&mode=agent&isNewChat=true',
      'prompt': 'prefill',
    },
  },
  'junie-cli': <String, Object?>{
    'name': 'Junie CLI',
    'aliases': <String>['Junie CLI', 'Junie'],
    'newSession': <String, Object?>{
      'command': <String>['junie'],
      'promptArguments': <String>['--prompt', '{prompt}'],
      'prompt': 'send',
    },
  },
  'kilo-cli': <String, Object?>{
    'name': 'Kilo CLI',
    'aliases': <String>['Kilo CLI', 'Kilo Code CLI'],
    'launch': <String, Object?>{
      'command': <String>['kilo', '--session', '{id}'],
    },
    'newSession': <String, Object?>{
      'command': <String>['kilo'],
      'promptArguments': <String>['--prompt', '{prompt}'],
      'prompt': 'send',
    },
  },
  'cline': <String, Object?>{
    'name': 'Cline',
    'aliases': <String>['Cline'],
    'newSession': <String, Object?>{
      'uri': 'vscode://saoudrizwan.claude-dev/task?prompt={prompt}',
      'prompt': 'send',
    },
  },
  'devin-cli': <String, Object?>{
    'name': 'Devin CLI',
    'aliases': <String>['Devin CLI', 'Devin Local'],
    'launch': <String, Object?>{
      'command': <String>['devin', '--resume', '{id}'],
    },
    'newSession': <String, Object?>{
      'command': <String>['devin'],
      'promptArguments': <String>['--', '{prompt}'],
      'prompt': 'send',
    },
  },
  'zed': <String, Object?>{
    'name': 'Zed',
    'aliases': <String>['Zed'],
    'newSession': <String, Object?>{
      'uri': 'zed://agent?prompt={prompt}',
      'prompt': 'prefill',
    },
  },
  'goose-desktop': <String, Object?>{
    'name': 'Goose Desktop',
    'aliases': <String>['Goose Desktop'],
    'launch': <String, Object?>{'uri': 'goose://resume/{id}'},
    'newSession': <String, Object?>{
      'uri': 'goose://new-session?prompt={prompt}',
      'prompt': 'prefill',
    },
  },
  'aider': <String, Object?>{
    'name': 'Aider',
    'aliases': <String>['Aider'],
    // `--message` sends one message and exits, so a new session has no prompt.
    'newSession': <String, Object?>{
      'command': <String>['aider'],
    },
  },
  'amp': <String, Object?>{
    'name': 'Amp',
    'aliases': <String>['Amp', 'Amp CLI'],
    'launch': <String, Object?>{
      'command': <String>['amp', 'threads', 'continue', '{id}'],
    },
    // Amp takes an interactive first message only on stdin.
    'newSession': <String, Object?>{
      'command': <String>['amp'],
    },
  },
  'windsurf': <String, Object?>{
    'name': 'Windsurf',
    'aliases': <String>['Windsurf'],
  },
  'unknown': <String, Object?>{'name': 'Unknown', 'ambiguous': true},
};
