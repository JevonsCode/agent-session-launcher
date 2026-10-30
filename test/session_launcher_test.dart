import 'dart:io';

import 'package:agent_session_launcher/agent_session_launcher.dart';
import 'package:agent_session_launcher/src/platform.dart'
    show windowsStartProcessScript;
import 'package:test/test.dart';

Matcher failsWith(String code) =>
    throwsA(isA<SessionLaunchException>().having((e) => e.code, 'code', code));

void main() {
  group('client identity', () {
    test('Claude Desktop entrypoint does not become Claude Code CLI', () {
      expect(
        classifyAgentSource('Claude Code', claudeEntrypoint: 'claude-desktop'),
        'claude-desktop',
      );
      expect(classifyAgentSource('Claude Code'), 'claude-code-unknown');
      expect(classifyAgentSource('Claude Code CLI'), 'claude-code');
      expect(classifyAgentSource('Claude'), 'unknown');
      expect(
        classifyAgentSource('Pi', claudeEntrypoint: 'claude-desktop'),
        'pi',
      );
    });
    test('ambiguous desktop and CLI labels stay distinct', () {
      expect(classifyAgentSource('OpenCode'), 'opencode');
      expect(classifyAgentSource('OpenCode Desktop'), 'opencode-desktop');
      expect(classifyAgentSource('OpenCode CLI'), 'opencode-cli');
      expect(classifyAgentSource('Antigravity IDE'), 'antigravity-ide');
      expect(classifyAgentSource('GitHub Copilot CLI'), 'copilot-cli');
      expect(classifyAgentSource('Grok Web'), 'unknown');
      expect(classifyAgentSource('Codex Desktop'), 'codex-desktop');
      expect(classifyAgentSource('Codex CLI'), 'codex-cli');
    });
  });

  group('fixed targets', () {
    final launcher = SessionLauncher(operatingSystem: 'macos');
    const id = 'a45cce14-b0be-4aea-a8f9-e88195674770';
    test('Desktop uses its native identifier, never the CLI id', () {
      final plan = launcher.inspect(
        const SessionTarget(
          client: 'claude-desktop',
          conversationId: id,
          hostSessionId: 'local_desktop-123',
        ),
      );
      expect(plan.kind, 'uri');
      expect(
        plan.uri.toString(),
        'claude://code/continue?session=local_desktop-123',
      );
      expect(
        () => launcher.inspect(
          const SessionTarget(client: 'claude-desktop', conversationId: id),
        ),
        failsWith('invalid_target'),
      );
    });
    test(
      'CLI sessions use the corresponding fixed executable and exact id',
      () {
        for (final (client, command, args) in <(String, String, List<String>)>[
          ('claude-code', 'claude', ['--resume', id]),
          ('pi', 'pi', ['--session', id]),
          ('opencode-cli', 'opencode', ['--session', id]),
          ('antigravity-cli', 'agy', ['--conversation', id]),
          ('copilot-cli', 'copilot', ['--resume', id]),
          ('grok-build', 'grok', ['--resume', id]),
          ('gemini-cli', 'gemini', ['--resume', id]),
          ('kiro-cli', 'kiro-cli', ['chat', '--resume-id', id]),
          ('codex-cli', 'codex', ['resume', id]),
        ]) {
          final plan = launcher.inspect(
            SessionTarget(
              client: client,
              conversationId: id,
              workspacePath: '/workspace',
            ),
          );
          expect(plan.kind, 'cli', reason: client);
          expect(plan.executable, command, reason: client);
          expect(plan.arguments, args, reason: client);
        }
      },
    );
    test('unknown surfaces never silently fall back to a CLI', () {
      for (final client in [
        'codex',
        'opencode',
        'opencode-desktop',
        'antigravity',
        'antigravity-ide',
        'antigravity-app',
        'copilot',
        'windsurf',
        'unknown',
      ]) {
        expect(
          () => launcher.inspect(
            SessionTarget(
              client: client,
              conversationId: id,
              workspacePath: '/workspace',
            ),
          ),
          failsWith('unsupported_client'),
          reason: client,
        );
      }
    });
    test(
      'rejects missing, partial and injection-shaped identifiers and paths',
      () {
        expect(
          () => launcher.inspect(
            const SessionTarget(
              client: 'pi',
              conversationId: 'a45cce14',
              workspacePath: '/workspace',
            ),
          ),
          failsWith('invalid_target'),
        );
        expect(
          () => launcher.inspect(
            const SessionTarget(
              client: 'claude-code',
              conversationId: 'id;rm',
              workspacePath: '/workspace',
            ),
          ),
          failsWith('invalid_target'),
        );
        expect(
          () => launcher.inspect(
            const SessionTarget(
              client: 'claude-code',
              conversationId: id,
              workspacePath: 'relative',
            ),
          ),
          failsWith('invalid_target'),
        );
        expect(
          () => launcher.inspect(
            const SessionTarget(
              client: 'claude-code',
              conversationId: id,
              workspacePath: '/work\nspace',
            ),
          ),
          failsWith('invalid_target'),
        );
        expect(
          () => launcher.inspect(
            const SessionTarget(
              client: 'claude-code',
              conversationId: id,
              workspacePath: '/workspace ',
            ),
          ),
          failsWith('invalid_target'),
        );
      },
    );
    test('Codex and Cursor background links use only allowed URI shapes', () {
      expect(
        launcher
            .inspect(
              const SessionTarget(client: 'codex-desktop', conversationId: id),
            )
            .uri
            .toString(),
        'codex://threads/$id',
      );
      expect(
        launcher
            .inspect(
              const SessionTarget(client: 'cursor', conversationId: 'bc-123'),
            )
            .uri
            .toString(),
        'cursor://anysphere.cursor-deeplink/background-agent?bcId=bc-123',
      );
      expect(
        () => launcher.inspect(
          const SessionTarget(
            client: 'cursor',
            conversationId: 'normal-session',
            workspacePath: '/workspace',
          ),
        ),
        failsWith('unsupported_target'),
      );
    });
  });

  test(
    'Linux CLI plans are explicit about lack of an interactive launcher',
    () {
      final launcher = SessionLauncher(operatingSystem: 'linux');
      final plan = launcher.inspect(
        const SessionTarget(
          client: 'claude-code',
          conversationId: 'session-123',
          workspacePath: '/workspace',
        ),
      );
      expect(launcher.supportsOpening(plan), isFalse);
    },
  );

  test('Windows plans accept absolute drive and UNC paths only', () {
    final launcher = SessionLauncher(operatingSystem: 'windows');
    const id = 'a45cce14-b0be-4aea-a8f9-e88195674770';
    for (final workspace in <String>[
      r'C:\project',
      r'\\server\share\project',
    ]) {
      final plan = launcher.inspect(
        SessionTarget(
          client: 'pi',
          conversationId: id,
          workspacePath: workspace,
        ),
      );
      expect(plan.workspacePath, workspace);
      expect(launcher.supportsOpening(plan), isTrue);
    }
    expect(
      () => launcher.inspect(
        const SessionTarget(
          client: 'pi',
          conversationId: id,
          workspacePath: r'C:relative',
        ),
      ),
      failsWith('invalid_target'),
    );
    expect(
      () => launcher.inspect(
        const SessionTarget(
          client: 'pi',
          conversationId: id,
          workspacePath: r'\\server',
        ),
      ),
      failsWith('invalid_target'),
    );
  });

  test(
    'iTerm new-tab mode uses the selected app without silent fallback',
    () async {
      final temp = await Directory.systemTemp.createTemp('agent-launch-iterm-');
      addTearDown(() => temp.delete(recursive: true));
      List<String>? arguments;
      final launcher = SessionLauncher(
        operatingSystem: 'macos',
        processRunner: (command, args, {workingDirectory}) async {
          arguments = args;
          return ProcessResult(1, 0, '', '');
        },
      );
      await launcher.open(
        SessionTarget(
          client: 'claude-code',
          conversationId: 'session-123',
          workspacePath: temp.path,
        ),
        preferences: const LaunchPreferences(
          macosTerminal: MacosTerminal.iterm,
          itermOpenMode: ITermOpenMode.newTab,
        ),
      );
      expect(arguments!.last, contains('tell application "iTerm"'));
      expect(arguments!.last, contains('create tab with default profile)'));
      expect(
        arguments!.last,
        contains('tell current session of newTab to write text'),
      );
      expect(
        arguments!.last,
        contains('tell current session of newWindow to write text'),
      );
      expect(arguments!.last, isNot(contains('default profile command')));
      expect(arguments!.last, isNot(contains('tell application "Terminal"')));
      await launcher.open(
        SessionTarget(
          client: 'claude-code',
          conversationId: 'session-123',
          workspacePath: temp.path,
        ),
        preferences: const LaunchPreferences(
          macosTerminal: MacosTerminal.iterm,
          itermOpenMode: ITermOpenMode.newWindow,
        ),
      );
      expect(arguments!.last, contains('create window with default profile)'));
      expect(
        arguments!.last,
        contains('tell current session of newWindow to write text'),
      );
      expect(arguments!.last, isNot(contains('default profile command')));
    },
    skip: Platform.isWindows
        ? 'A simulated macOS workspace needs a POSIX temporary path.'
        : false,
  );

  test(
    'macOS launches a fixed CLI through Terminal with quoted workspace',
    () async {
      final temp = await Directory.systemTemp.createTemp('agent-launch-test-');
      addTearDown(() => temp.delete(recursive: true));
      final workspace = Directory('${temp.path}/project; harmless');
      await workspace.create();
      String? executable;
      List<String>? arguments;
      final launcher = SessionLauncher(
        operatingSystem: 'macos',
        processRunner: (command, args, {workingDirectory}) async {
          executable = command;
          arguments = args;
          return ProcessResult(1, 0, '', '');
        },
      );
      await launcher.open(
        SessionTarget(
          client: 'pi',
          conversationId: 'a45cce14-b0be-4aea-a8f9-e88195674770',
          workspacePath: workspace.path,
        ),
      );
      expect(executable, '/usr/bin/osascript');
      expect(arguments, hasLength(2));
      expect(arguments!.first, '-e');
      expect(
        arguments!.last,
        contains("cd -- '${workspace.path}' && exec 'pi' '--session'"),
      );
    },
    skip: Platform.isWindows
        ? 'A simulated macOS workspace needs a POSIX temporary path.'
        : false,
  );

  group('Windows openers', () {
    ProcessRunner recorder(
      List<(String, List<String>)> calls, {
      int exitCode = 0,
    }) => (command, args, {workingDirectory}) async {
      calls.add((command, args));
      return ProcessResult(1, exitCode, '', '');
    };

    test('an explorer.exe exit code alone is not a failed launch', () async {
      final calls = <(String, List<String>)>[];
      final launcher = SessionLauncher(
        operatingSystem: 'windows',
        processRunner: recorder(calls, exitCode: 1),
      );
      await launcher.open(
        const SessionTarget(
          client: 'codex-desktop',
          conversationId: 'a45cce14-b0be-4aea-a8f9-e88195674770',
        ),
      );
      expect(calls.single.$1, 'explorer.exe');
      expect(calls.single.$2, <String>[
        'codex://threads/a45cce14-b0be-4aea-a8f9-e88195674770',
      ]);
    });

    test('explorer.exe that cannot start still fails the launch', () async {
      final launcher = SessionLauncher(
        operatingSystem: 'windows',
        processRunner: (command, args, {workingDirectory}) async =>
            throw ProcessException(command, args, 'not found', 2),
      );
      expect(
        launcher.open(
          const SessionTarget(
            client: 'codex-desktop',
            conversationId: 'a45cce14-b0be-4aea-a8f9-e88195674770',
          ),
        ),
        failsWith('launch_failed'),
      );
    });

    test('other openers still fail on a non-zero exit code', () async {
      final calls = <(String, List<String>)>[];
      final launcher = SessionLauncher(
        operatingSystem: 'linux',
        processRunner: recorder(calls, exitCode: 1),
      );
      await expectLater(
        launcher.open(
          const SessionTarget(
            client: 'codex-desktop',
            conversationId: 'a45cce14-b0be-4aea-a8f9-e88195674770',
          ),
        ),
        failsWith('launch_failed'),
      );
      expect(calls.single.$1, 'xdg-open');
    });

    test('the plan names the Windows CLI opener', () {
      const target = SessionTarget(
        client: 'claude-code',
        conversationId: 'session-123',
        workspacePath: r'C:\work',
      );
      final withTerminal = SessionLauncher(
        operatingSystem: 'windows',
        commandAvailable: (command) => command == 'wt.exe',
      ).inspect(target);
      expect(withTerminal.toJson()['opener'], 'windows-terminal');
      final without = SessionLauncher(
        operatingSystem: 'windows',
        commandAvailable: (command) => false,
      ).inspect(target);
      expect(without.toJson()['opener'], 'powershell');
      expect(
        SessionLauncher(
          operatingSystem: 'macos',
        ).inspect(target.withWorkspace('/work')).toJson(),
        isNot(contains('opener')),
      );
      expect(
        SessionLauncher(
              operatingSystem: 'windows',
              commandAvailable: (_) => false,
            )
            .inspect(
              const SessionTarget(
                client: 'codex-desktop',
                conversationId: 'a45cce14-b0be-4aea-a8f9-e88195674770',
              ),
            )
            .toJson(),
        isNot(contains('opener')),
      );
    });

    test('the PowerShell fallback quotes every value as a literal', () {
      final String script = windowsStartProcessScript(
        const LaunchPlan(
          kind: 'cli',
          executable: r'C:\Tools (x86)\agent.exe',
          arguments: <String>['--resume', 'session-123'],
          workspacePath:
              "C:\work\it's [draft] \u2019quoted\u2019 \$HOME %PATH%",
        ),
      );
      expect(script, startsWith(r"$ErrorActionPreference = 'Stop'; "));
      expect(script, contains(r"$info.FileName = 'C:\Tools (x86)\agent.exe'"));
      expect(script, contains(r"$info.Arguments = '--resume session-123'"));
      expect(
        script,
        contains(
          "\$info.WorkingDirectory = 'C:\work\it''s [draft] "
          "\u2019\u2019quoted\u2019\u2019 \$HOME %PATH%'",
        ),
      );
      expect(script, contains(r'$info.UseShellExecute = $true'));
      expect(script, isNot(contains('Start-Process')));
    });

    test(
      'without Windows Terminal a CLI opens through PowerShell',
      () async {
        final temp = await Directory.systemTemp.createTemp("agent-launch-'w ");
        addTearDown(() => temp.delete(recursive: true));
        final calls = <(String, List<String>)>[];
        final launcher = SessionLauncher(
          operatingSystem: 'windows',
          processRunner: recorder(calls),
          commandAvailable: (_) => false,
        );
        await launcher.open(
          SessionTarget(
            client: 'claude-code',
            conversationId: 'session-123',
            workspacePath: temp.path,
          ),
        );
        expect(calls.single.$1, 'powershell.exe');
        expect(calls.single.$2.take(3), <String>[
          '-NoProfile',
          '-NonInteractive',
          '-Command',
        ]);
        expect(
          calls.single.$2.last,
          contains(
            "\$info.WorkingDirectory = '${temp.path.replaceAll("'", "''")}'",
          ),
        );

        calls.clear();
        await SessionLauncher(
          operatingSystem: 'windows',
          processRunner: recorder(calls),
          commandAvailable: (_) => true,
        ).open(
          SessionTarget(
            client: 'claude-code',
            conversationId: 'session-123',
            workspacePath: temp.path,
          ),
        );
        expect(calls.single.$1, 'wt.exe');
        expect(calls.single.$2, <String>[
          '-d',
          temp.path,
          'claude',
          '--resume',
          'session-123',
        ]);
      },
      skip: Platform.isWindows
          ? false
          : 'A simulated Windows workspace needs a drive-letter path.',
    );
  });
}

extension on SessionTarget {
  SessionTarget withWorkspace(String path) => SessionTarget(
    client: client,
    conversationId: conversationId,
    hostSessionId: hostSessionId,
    workspacePath: path,
  );
}
