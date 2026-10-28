import 'dart:io';

import 'package:agent_session_launcher/agent_session_launcher.dart';
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
}
