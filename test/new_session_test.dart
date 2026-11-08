import 'dart:convert';
import 'dart:io';

import 'package:agent_session_launcher/agent_session_launcher.dart';
import 'package:agent_session_launcher/protocol.dart';
import 'package:agent_session_launcher/src/platform.dart'
    show
        encodePowerShellCommand,
        linuxTerminalArguments,
        windowsArgument,
        windowsBatchArgument,
        windowsNewSessionScript,
        wslPlan;
import 'package:test/test.dart';

Matcher failsWith(String code) =>
    throwsA(isA<SessionLaunchException>().having((e) => e.code, 'code', code));

/// Prompts that break naive quoting in at least one opener.
const List<String> hardPrompts = <String>[
  '#FLA Tonborg 给我讲讲待决策里你拿不准的事',
  'say "hi" & echo pwned | calc ^ %PATH% !x! ; \$(whoami) `id` \'q\'',
  r'trailing backslash \',
  r'back\\slash "quote\" C:\dir\ end',
  'line one\nline two\r\nline three',
  '100% done; 50%% left',
  'tab\there “typographic” ‘quotes’ – ok',
  'emoji 🧪 and CJK 汉字 ﹏ 。',
  "it's\t\$(touch pwned)\rend",
];

/// How the Microsoft C runtime splits a command line after the program name
/// (the 2008+ rules, `""` inside quotes is one quote).
List<String> parseWindowsArguments(String line) {
  final List<String> out = <String>[];
  int i = 0;
  while (true) {
    while (i < line.length && (line[i] == ' ' || line[i] == '\t')) {
      i++;
    }
    if (i >= line.length) return out;
    final StringBuffer arg = StringBuffer();
    bool quoted = false;
    while (i < line.length) {
      final String c = line[i];
      if (!quoted && (c == ' ' || c == '\t')) break;
      if (c == r'\') {
        int n = 0;
        while (i < line.length && line[i] == r'\') {
          n++;
          i++;
        }
        if (i < line.length && line[i] == '"') {
          arg.write(r'\' * (n ~/ 2));
          if (n.isOdd) {
            arg.write('"');
            i++;
          }
        } else {
          arg.write(r'\' * n);
        }
      } else if (c == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          arg.write('"');
          i += 2;
        } else {
          quoted = !quoted;
          i++;
        }
      } else {
        arg.write(c);
        i++;
      }
    }
    out.add(arg.toString());
  }
}

void main() {
  group('catalog', () {
    final launcher = SessionLauncher(operatingSystem: 'macos');
    test('CLI clients get the prompt as one argument, or nothing', () {
      for (final (client, executable, fixed, promptArgs)
          in <(String, String, List<String>, List<String>)>[
            ('claude-code', 'claude', [], ['P']),
            ('codex-cli', 'codex', [], ['P']),
            ('cursor-cli', 'agent', [], ['P']),
            ('pi', 'pi', [], ['P']),
            ('opencode-cli', 'opencode', [], ['--prompt', 'P']),
            ('antigravity-cli', 'agy', [], ['-i', 'P']),
            ('copilot-cli', 'copilot', [], ['-i', 'P']),
            ('gemini-cli', 'gemini', [], ['-i', 'P']),
            ('qwen-code', 'qwen', [], ['-i', 'P']),
            ('qoder-cli', 'qoder', [], ['-i', 'P']),
            ('junie-cli', 'junie', [], ['--prompt', 'P']),
            ('kilo-cli', 'kilo', [], ['--prompt', 'P']),
            ('devin-cli', 'devin', [], ['--', 'P']),
          ]) {
        const prompt = 'explain "this" 好吗';
        final plan = launcher.inspectNew(
          NewSessionTarget(
            client: client,
            prompt: prompt,
            workspacePath: '/work',
          ),
        );
        expect(plan.kind, 'cli', reason: client);
        expect(plan.newSession, isTrue);
        expect(plan.prompt, PromptHandling.send, reason: client);
        expect(plan.executable, executable, reason: client);
        expect(plan.arguments, <String>[
          ...fixed,
          for (final String a in promptArgs) a == 'P' ? prompt : a,
        ], reason: client);
        expect(plan.workspacePath, '/work');
        final bare = SessionLauncher(
          operatingSystem: 'macos',
          homeDirectory: '/home/someone/',
        ).inspectNew(NewSessionTarget(client: client));
        expect(bare.arguments, fixed, reason: client);
        expect(bare.prompt, isNull);
        expect(bare.workspacePath, '/home/someone');
      }
    });

    test('URI clients carry the prompt as one percent-encoded value', () {
      const prompt = '#FLA Tonborg 讲讲 a+b & c=d\n?';
      final encoded = Uri.encodeComponent(prompt);
      for (final (client, base, prompted, handling)
          in <(String, String, String, String)>[
            (
              'claude-desktop',
              'claude://code/new',
              'claude://code/new?q=$encoded',
              'prefill',
            ),
            (
              'claude-chat',
              'claude://claude.ai/new',
              'claude://claude.ai/new?q=$encoded',
              'prefill',
            ),
            (
              'claude-code-vscode',
              'vscode://anthropic.claude-code/open',
              'vscode://anthropic.claude-code/open?prompt=$encoded',
              'prefill',
            ),
            (
              'codex-desktop',
              'codex://new',
              'codex://new?prompt=$encoded',
              'prefill',
            ),
            (
              'cursor',
              'cursor://anysphere.cursor-deeplink/prompt',
              'cursor://anysphere.cursor-deeplink/prompt?text=$encoded',
              'prefill',
            ),
            (
              'copilot-ide',
              'vscode://github.copilot-chat/chat',
              'vscode://github.copilot-chat/chat?prompt=$encoded',
              'prefill',
            ),
            (
              'cline',
              'vscode://saoudrizwan.claude-dev/task',
              'vscode://saoudrizwan.claude-dev/task?prompt=$encoded',
              'send',
            ),
            (
              'qoder',
              'qoder://aicoding.aicoding-deeplink/chat?mode=agent&isNewChat=true',
              'qoder://aicoding.aicoding-deeplink/chat?text=$encoded&mode=agent&isNewChat=true',
              'prefill',
            ),
            ('zed', 'zed://agent', 'zed://agent?prompt=$encoded', 'prefill'),
            (
              'goose-desktop',
              'goose://new-session',
              'goose://new-session?prompt=$encoded',
              'prefill',
            ),
          ]) {
        final plan = launcher.inspectNew(
          NewSessionTarget(client: client, prompt: prompt),
        );
        expect(plan.uri.toString(), prompted, reason: client);
        expect(plan.prompt, handling, reason: client);
        expect(plan.uri!.queryParametersAll.values.expand((v) => v), <Object>[
          ...<String>[prompt],
          ...?(client == 'qoder' ? <String>['agent', 'true'] : null),
        ], reason: client);
        expect(
          launcher.inspectNew(NewSessionTarget(client: client)).uri.toString(),
          base,
          reason: client,
        );
        expect(prompted, isNot(contains('+')), reason: client);
      }
    });

    test('a prompt-less way refuses a prompt; unknown clients refuse', () {
      expect(
        launcher
            .inspectNew(
              const NewSessionTarget(client: 'aider', workspacePath: '/w'),
            )
            .arguments,
        isEmpty,
      );
      expect(
        () => launcher.inspectNew(
          const NewSessionTarget(client: 'aider', prompt: 'hi'),
        ),
        failsWith('unsupported_prompt'),
      );
      for (final client in <String>[
        'windsurf',
        'opencode',
        'codex',
        'antigravity-ide',
        'grok-build',
        'nope',
      ]) {
        expect(
          () => launcher.inspectNew(NewSessionTarget(client: client)),
          failsWith('unsupported_client'),
          reason: client,
        );
      }
    });

    test('clients() reports each new-session way', () {
      final byId = <String, ClientInfo>{
        for (final c in SessionLauncher(operatingSystem: 'windows').clients())
          c.id: c,
      };
      expect(byId['gemini-cli']!.newSession!.toJson(), <String, Object?>{
        'kind': 'cli',
        'prompt': 'send',
        'openSupported': true,
      });
      expect(byId['aider']!.newSession!.prompt, isNull);
      expect(byId['kiro-cli']!.newSession!.prompt, isNull);
      expect(byId['windsurf']!.newSession, isNull);
    });
  });

  group('prompt rules', () {
    final launcher = SessionLauncher(
      operatingSystem: 'macos',
      homeDirectory: '/home/someone',
    );
    test('refuses empty, oversized, control and option-shaped prompts', () {
      for (final prompt in <String>[
        '',
        '   ',
        'x' * 2001,
        'bell\x07',
        'escape \x1b[31m',
        'nul\x00',
        '--dangerously-skip-permissions',
        '-x',
      ]) {
        expect(
          () => launcher.inspectNew(
            NewSessionTarget(client: 'claude-code', prompt: prompt),
          ),
          failsWith('invalid_prompt'),
          reason: jsonEncode(prompt),
        );
      }
      // An option-shaped text is harmless inside a URI value.
      expect(
        launcher
            .inspectNew(
              const NewSessionTarget(client: 'codex-desktop', prompt: '-x'),
            )
            .uri
            .toString(),
        'codex://new?prompt=-x',
      );
      expect(
        launcher
            .inspectNew(
              NewSessionTarget(client: 'claude-code', prompt: 'x' * 2000),
            )
            .arguments
            .single
            .length,
        2000,
      );
    });
    test('a relative or broken workspace is refused', () {
      for (final workspace in <String>['relative', '/a\nb', '/w ']) {
        expect(
          () => launcher.inspectNew(
            NewSessionTarget(client: 'claude-code', workspacePath: workspace),
          ),
          failsWith('invalid_target'),
        );
      }
    });
  });

  group('WSL', () {
    test('wraps the client in wsl.exe and bash, the prompt as data', () {
      final launcher = SessionLauncher(
        operatingSystem: 'windows',
        homeDirectory: r'C:\Users\someone',
        commandAvailable: (_) => true,
      );
      final plan = launcher.inspectNew(
        const NewSessionTarget(
          client: 'opencode-cli',
          prompt: r'x "$(rm -rf ~)" `id`',
          environment: 'wsl',
        ),
      );
      expect(plan.executable, 'wsl.exe');
      expect(plan.environment, 'wsl');
      expect(plan.opener, WindowsOpener.windowsTerminal);
      expect(plan.workspacePath, r'C:\Users\someone');
      expect(plan.arguments, <String>[
        '--cd',
        '~',
        '--exec',
        'bash',
        '-lic',
        r'p=$0; case $p in "~/"*) p=$HOME/${p#"~/"};; esac; exec "$p" "$@"',
        'opencode',
        '--prompt',
        r'x "$(rm -rf ~)" `id`',
      ]);
      expect(
        launcher
            .inspectNew(
              const NewSessionTarget(
                client: 'opencode-cli',
                workspacePath: r'D:\repo',
                environment: 'wsl',
              ),
            )
            .arguments
            .take(2),
        <String>['--cd', r'D:\repo'],
      );
    });
    test('only a CLI on Windows runs in WSL', () {
      expect(
        () => SessionLauncher(operatingSystem: 'macos').inspectNew(
          const NewSessionTarget(client: 'opencode-cli', environment: 'wsl'),
        ),
        failsWith('invalid_target'),
      );
      expect(
        () => SessionLauncher(operatingSystem: 'windows').inspectNew(
          const NewSessionTarget(client: 'codex-desktop', environment: 'wsl'),
        ),
        failsWith('invalid_target'),
      );
      expect(
        () => SessionLauncher(operatingSystem: 'windows').inspectNew(
          const NewSessionTarget(client: 'opencode-cli', environment: 'linux'),
        ),
        failsWith('invalid_target'),
      );
    });
    test('the bash wrapper passes every argument through unchanged', () async {
      final result = await Process.run('bash', <String>[
        '-c',
        r'p=$0; case $p in "~/"*) p=$HOME/${p#"~/"};; esac; exec "$p" "$@"',
        'printf',
        r'%s\0',
        ...hardPrompts,
      ]);
      expect(result.exitCode, 0);
      expect(
        (result.stdout as String).split('\x00')..removeLast(),
        hardPrompts,
      );
    }, skip: Platform.isWindows ? 'Needs bash.' : false);
  });

  test(
    'a real round trip through PowerShell, wsl.exe and bash',
    () async {
      final probe = Process.runSync('wsl.exe', <String>['--exec', 'true']);
      if (probe.exitCode != 0) {
        markTestSkipped('No WSL distribution.');
        return;
      }
      final temp = await Directory.systemTemp.createTemp('new-session-wsl-');
      addTearDown(() => temp.delete(recursive: true));
      final plan = wslPlan(
        LaunchPlan(
          kind: 'cli',
          executable: 'printf',
          // NUL does not survive WSL's console relay; a visible separator does.
          arguments: <String>['%s<|>', 'BEGIN', ...hardPrompts],
          newSession: true,
        ),
        linuxDirectory: null,
        windowsDirectory: temp.path,
      );
      final result = await Process.run('powershell.exe', <String>[
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-EncodedCommand',
        encodePowerShellCommand(windowsNewSessionScript(plan)),
      ], stdoutEncoding: utf8);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      // The person's shell profile may print a banner first.
      final output = result.stdout as String;
      final begin = output.indexOf('BEGIN<|>');
      expect(begin, isNonNegative, reason: output);
      final parts = output.substring(begin + 'BEGIN<|>'.length).split('<|>');
      expect(parts.sublist(0, parts.length - 1), hardPrompts);
    },
    skip: Platform.isWindows ? false : 'Needs Windows.',
    timeout: const Timeout(Duration(minutes: 2)),
  );

  group('Windows quoting', () {
    test('C runtime arguments round-trip', () {
      for (final value in <String>[...hardPrompts, '', 'plain', r'a\\b']) {
        expect(parseWindowsArguments(windowsArgument(value)), <String>[
          value,
        ], reason: jsonEncode(value));
      }
    });
    test('batch arguments stay quoted, defuse % and round-trip', () {
      for (final value in hardPrompts) {
        final quoted = windowsBatchArgument(value);
        expect(quoted, startsWith('"'));
        expect(quoted, endsWith('"'));
        // cmd.exe toggles quoting on every `"`; an even count keeps every
        // special character inside quotes.
        expect('"'.allMatches(quoted).length.isEven, isTrue);
        expect(quoted, isNot(matches(RegExp(r'[\r\n]'))));
        expect(
          parseWindowsArguments(quoted.replaceAll('%%cd:~,%', '%')),
          <String>[value.replaceAll(RegExp(r'\r\n|\r|\n'), ' ')],
          reason: jsonEncode(value),
        );
      }
      expect(windowsBatchArgument('%PATH%'), '"%%cd:~,%PATH%%cd:~,%"');
    });
    test('the host script holds values only as single-quoted literals', () {
      final script = windowsNewSessionScript(
        const LaunchPlan(
          kind: 'cli',
          executable: 'claude',
          arguments: <String>["it's ‘odd’"],
          workspacePath: r"C:\it's",
          newSession: true,
        ),
      );
      expect(script, contains(r"$name = 'claude'"));
      expect(script, contains(r"""$info.Arguments = '"it''s ‘‘odd’’"'"""));
      expect(script, contains(r"$info.WorkingDirectory = 'C:\it''s'"));
      final decoded = encodePowerShellCommand('é汉🧪');
      expect(base64.decode(decoded), <int>[
        0xE9,
        0,
        0x49,
        0x6C,
        0x3E,
        0xD8,
        0xEA,
        0xDD,
      ]);
    });

    test(
      'opening uses one encoded script in Windows Terminal or a console',
      () async {
        final temp = await Directory.systemTemp.createTemp('new-session-');
        addTearDown(() => temp.delete(recursive: true));
        for (final hasTerminal in <bool>[true, false]) {
          String? executable;
          List<String>? arguments;
          final launcher = SessionLauncher(
            operatingSystem: 'windows',
            commandAvailable: (_) => hasTerminal,
            processRunner: (command, args, {workingDirectory}) async {
              executable = command;
              arguments = args;
              return ProcessResult(1, 0, '', '');
            },
          );
          await launcher
              .openNew(
                NewSessionTarget(
                  client: 'gemini-cli',
                  prompt: hardPrompts[1],
                  workspacePath: r'C:\Windows',
                ),
              )
              .catchError((Object e) {
                // The workspace check needs a real directory off Windows.
                if (Platform.isWindows) throw e;
              });
          if (!Platform.isWindows) continue;
          if (hasTerminal) {
            expect(executable, 'wt.exe');
            expect(arguments!.take(4), <String>[
              'powershell.exe',
              '-NoLogo',
              '-NoProfile',
              '-EncodedCommand',
            ]);
            expect(arguments!.last, matches(RegExp(r'^[A-Za-z0-9+/=]+$')));
          } else {
            expect(executable, 'powershell.exe');
            expect(arguments!.last, contains('-EncodedCommand '));
            expect(arguments!.last, isNot(contains('pwned')));
          }
        }
      },
    );

    test(
      'a real round-trip through PowerShell, an .exe and a .cmd shim',
      () async {
        final node =
            (Process.runSync('where.exe', <String>['node']).stdout as String)
                .split(RegExp(r'\r?\n'))
                .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '')
                .trim();
        if (node.isEmpty) {
          markTestSkipped('node is not on PATH');
          return;
        }
        final temp = await Directory.systemTemp.createTemp('new-session-');
        addTearDown(() => temp.delete(recursive: true));
        final out = File('${temp.path}\\out.json');
        File('${temp.path}\\dump.js').writeAsStringSync(
          'require("fs").writeFileSync(${jsonEncode(out.path)}, '
          'JSON.stringify(process.env.CLAUDE_CODE_CHILD_SESSION === undefined '
          '? process.argv.slice(2) : ["inherited a parent session marker"]));',
        );
        final shim = File('${temp.path}\\dump-args.cmd')
          ..writeAsStringSync('@ECHO off\r\n"$node" "%~dp0\\dump.js" %*\r\n');
        Future<List<String>> run(String executable, List<String> args) async {
          if (out.existsSync()) out.deleteSync();
          final plan = LaunchPlan(
            kind: 'cli',
            executable: executable,
            arguments: args,
            workspacePath: temp.path,
            newSession: true,
          );
          final result = await Process.run(
            'powershell.exe',
            <String>[
              '-NoLogo',
              '-NoProfile',
              '-NonInteractive',
              '-EncodedCommand',
              encodePowerShellCommand(windowsNewSessionScript(plan)),
            ],
            environment: <String, String>{'CLAUDE_CODE_CHILD_SESSION': '1'},
          );
          expect(result.exitCode, 0, reason: '${result.stdout}');
          return (jsonDecode(out.readAsStringSync()) as List).cast<String>();
        }

        // node.exe stands in for a native client such as claude.exe.
        expect(
          await run(node, <String>['${temp.path}\\dump.js', ...hardPrompts]),
          hardPrompts,
        );
        // An npm-style shim such as codex.cmd, through cmd.exe.
        expect(await run(shim.path, hardPrompts), <String>[
          for (final p in hardPrompts) p.replaceAll(RegExp(r'\r\n|\r|\n'), ' '),
        ]);
      },
      skip: Platform.isWindows ? false : 'Needs Windows.',
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  group('POSIX terminals', () {
    test(
      'the macOS command and the Linux argv round-trip through sh',
      () async {
        final temp = await Directory.systemTemp.createTemp('new-session-');
        addTearDown(() => temp.delete(recursive: true));
        final workspace = Directory('${temp.path}/it\'s a "dir"')..createSync();
        final out = File('${temp.path}/out');
        final dump = File('${temp.path}/dump')
          ..writeAsStringSync(
            '#!/bin/sh\npwd -P > "${out.path}.pwd"\n'
            'for a; do printf \'%s\\0\' "\$a"; done > "${out.path}"\n',
          );
        Process.runSync('chmod', <String>['+x', dump.path]);
        final config = LauncherConfig.fromJson(<String, Object?>{
          'schemaVersion': 1,
          'clients': <String, Object?>{
            'dump': <String, Object?>{
              'newSession': <String, Object?>{
                'command': <String>[dump.path],
                'promptArguments': <String>['{prompt}'],
                'prompt': 'send',
              },
            },
          },
        });
        List<String> read() =>
            out.readAsStringSync().split('\x00')..removeLast();
        for (final prompt in hardPrompts) {
          String? script;
          await SessionLauncher(
            operatingSystem: 'macos',
            config: config,
            processRunner: (command, args, {workingDirectory}) async {
              script = args.last;
              return ProcessResult(1, 0, '', '');
            },
          ).openNew(
            NewSessionTarget(
              client: 'dump',
              prompt: prompt,
              workspacePath: workspace.path,
            ),
          );
          // Terminal types the command `do script` holds: undo AppleScript's
          // string escapes. It is only the path of a script file, so no tab
          // or line break of the prompt ever reaches an interactive shell.
          final quoted = RegExp(
            r'do script "((?:[^"\\]|\\.)*)"',
          ).firstMatch(script!)!.group(1)!;
          final command = quoted.replaceAllMapped(
            RegExp(r'\\(.)', dotAll: true),
            (m) => m[1]!,
          );
          final typed = RegExp(
            r"^exec /bin/sh '([^'\t\r\n]+)'$",
          ).firstMatch(command);
          expect(typed, isNotNull, reason: command);
          final file = File(typed!.group(1)!);
          expect(file.existsSync(), isTrue);
          expect(Process.runSync('sh', <String>['-c', command]).exitCode, 0);
          expect(
            file.parent.existsSync(),
            isFalse,
            reason: 'it removes itself',
          );
          expect(read(), <String>[prompt], reason: jsonEncode(prompt));
          expect(
            File('${out.path}.pwd').readAsStringSync().trim(),
            workspace.resolveSymbolicLinksSync(),
          );

          List<String>? argv;
          await SessionLauncher(
            operatingSystem: 'linux',
            config: config,
            commandAvailable: (c) => c == 'xterm',
            detachedStarter: (_, args) async => argv = args,
          ).openNew(
            NewSessionTarget(
              client: 'dump',
              prompt: prompt,
              workspacePath: workspace.path,
            ),
          );
          expect(argv!.first, '-e');
          out.deleteSync();
          final linux = Process.runSync(argv![1], argv!.sublist(2));
          expect(linux.exitCode, 0);
          expect(read(), <String>[prompt], reason: jsonEncode(prompt));
        }
        expect(
          linuxTerminalArguments(
            const LaunchPlan(
              kind: 'cli',
              executable: 'x',
              workspacePath: '/w',
              opener: 'gnome-terminal',
            ),
          ).take(2),
          <String>['--', 'sh'],
        );
      },
      skip: Platform.isWindows ? 'Needs a POSIX shell.' : false,
    );
  });

  group('protocol', () {
    test('inspect-new and open-new validate their own fields', () async {
      final launcher = SessionLauncher(
        operatingSystem: 'macos',
        processRunner: (command, args, {workingDirectory}) async =>
            ProcessResult(1, 0, '', ''),
      );
      final inspected = await handleRequest(<String, Object?>{
        'version': 1,
        'action': 'inspect-new',
        'target': <String, Object?>{'client': 'codex-desktop', 'prompt': '讲讲'},
      }, launcher: launcher);
      expect(inspected['ok'], isTrue);
      expect(inspected['plan'], <String, Object?>{
        'kind': 'uri',
        'uri': 'codex://new?prompt=%E8%AE%B2%E8%AE%B2',
        'newSession': true,
        'prompt': 'prefill',
      });
      final opened = await handleRequest(<String, Object?>{
        'version': 1,
        'action': 'open-new',
        'target': <String, Object?>{'client': 'cursor', 'prompt': 'hi'},
      }, launcher: launcher);
      expect(opened['status'], 'launch_requested');
      for (final target in <Map<String, Object?>>[
        <String, Object?>{'client': 'cursor', 'conversationId': 'x'},
        <String, Object?>{'client': 'cursor', 'prompt': 3},
        <String, Object?>{'client': 'cursor', 'command': 'calc'},
      ]) {
        final refused = await handleRequest(<String, Object?>{
          'version': 1,
          'action': 'inspect-new',
          'target': target,
        }, launcher: launcher);
        expect(refused['ok'], isFalse);
        expect(
          (refused['error']! as Map<String, Object?>)['code'],
          'invalid_request',
        );
      }
      final badPrompt = await handleRequest(<String, Object?>{
        'version': 1,
        'action': 'open-new',
        'target': <String, Object?>{'client': 'claude-code', 'prompt': '-rf'},
      }, launcher: launcher);
      expect(
        (badPrompt['error']! as Map<String, Object?>)['code'],
        'invalid_prompt',
      );
    });
  });

  group('configuration', () {
    LauncherConfig config(Map<String, Object?> client) =>
        LauncherConfig.fromJson(<String, Object?>{
          'schemaVersion': 1,
          'clients': <String, Object?>{'acme': client},
        });
    test('a host may describe its own client', () {
      final launcher = SessionLauncher(
        operatingSystem: 'macos',
        config: config(<String, Object?>{
          'newSession': <String, Object?>{
            'uri': 'acme://chat/new?draft={prompt}&src=fuli',
            'prompt': 'prefill',
          },
        }),
      );
      expect(
        launcher
            .inspectNew(const NewSessionTarget(client: 'acme', prompt: 'a b'))
            .uri
            .toString(),
        'acme://chat/new?draft=a%20b&src=fuli',
      );
    });
    test('rejects shell text, misplaced and missing prompt tokens', () {
      for (final spec in <Map<String, Object?>>[
        <String, Object?>{
          'command': <String>['acme', '; rm'],
        },
        <String, Object?>{
          'command': <String>['acme'],
          'promptArguments': <String>['--p'],
          'prompt': 'send',
        },
        <String, Object?>{
          'command': <String>['acme'],
          'promptArguments': <String>['{prompt}', '{prompt}'],
          'prompt': 'send',
        },
        <String, Object?>{
          'command': <String>['acme'],
          'promptArguments': <String>['{prompt}'],
        },
        <String, Object?>{
          'command': <String>['acme'],
          'promptArguments': <String>['{prompt}'],
          'prompt': 'run',
        },
        <String, Object?>{'uri': 'acme://x/{prompt}', 'prompt': 'prefill'},
        <String, Object?>{'uri': 'acme://x?q={prompt}'},
        <String, Object?>{'uri': 'https://x?q={prompt}', 'prompt': 'send'},
        <String, Object?>{
          'uri': 'acme://x',
          'command': <String>['a'],
        },
        <String, Object?>{'uri': 'acme://x', 'extra': true},
      ]) {
        expect(
          () => config(<String, Object?>{'newSession': spec}),
          failsWith('invalid_configuration'),
          reason: jsonEncode(spec),
        );
      }
    });
    test('a built-in client keeps its kind', () {
      expect(
        () => LauncherConfig.fromJson(<String, Object?>{
          'schemaVersion': 1,
          'clients': <String, Object?>{
            'claude-code': <String, Object?>{
              'newSession': <String, Object?>{
                'uri': 'acme://x?q={prompt}',
                'prompt': 'prefill',
              },
            },
          },
        }),
        failsWith('invalid_configuration'),
      );
      final custom = SessionLauncher(
        operatingSystem: 'macos',
        homeDirectory: '/home/someone',
        config: LauncherConfig.fromJson(<String, Object?>{
          'schemaVersion': 1,
          'clients': <String, Object?>{
            'claude-code': <String, Object?>{
              'newSession': <String, Object?>{
                'command': <String>['/opt/claude/bin/claude'],
                'promptArguments': <String>['{prompt}'],
                'prompt': 'send',
              },
            },
          },
        }),
      );
      expect(
        custom
            .inspectNew(
              const NewSessionTarget(client: 'claude-code', prompt: 'p'),
            )
            .executable,
        '/opt/claude/bin/claude',
      );
    });
  });
}
