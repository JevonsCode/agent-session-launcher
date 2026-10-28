import 'dart:io';

import 'models.dart';

/// Plans and opens interactive sessions; it never sends a prompt or runs a model.
final class SessionLauncher {
  SessionLauncher({String? operatingSystem, ProcessRunner? processRunner})
    : _operatingSystem = operatingSystem ?? Platform.operatingSystem,
      _processRunner = processRunner ?? _runProcess;

  final String _operatingSystem;
  final ProcessRunner _processRunner;

  bool supportsOpening(LaunchPlan plan) => plan.kind == 'uri'
      ? const <String>{'macos', 'windows', 'linux'}.contains(_operatingSystem)
      : const <String>{'macos', 'windows'}.contains(_operatingSystem);

  LaunchPlan inspect(SessionTarget target) {
    final String client = target.client.trim().toLowerCase();
    if (client == 'claude-desktop') {
      final String id = (target.hostSessionId ?? '').trim();
      if (!RegExp(r'^local_[A-Za-z0-9-]{1,64}$').hasMatch(id)) {
        throw const SessionLaunchException(
          'invalid_target',
          'A valid Claude Desktop host session ID is required.',
        );
      }
      return LaunchPlan(
        kind: 'uri',
        uri: Uri(
          scheme: 'claude',
          host: 'code',
          path: '/continue',
          queryParameters: <String, String>{'session': id},
        ),
      );
    }
    if (client == 'codex-desktop') {
      final String id = _validSessionId(target.conversationId);
      if (!_uuid.hasMatch(id)) {
        throw const SessionLaunchException(
          'invalid_target',
          'Codex requires a full UUID session ID.',
        );
      }
      return LaunchPlan(
        kind: 'uri',
        uri: Uri(scheme: 'codex', host: 'threads', pathSegments: <String>[id]),
      );
    }
    if (client == 'cursor') {
      final String id = _validSessionId(target.conversationId);
      if (!id.startsWith('bc-')) {
        throw const SessionLaunchException(
          'unsupported_target',
          'Only Cursor background-agent links are supported.',
        );
      }
      return LaunchPlan(
        kind: 'uri',
        uri: Uri(
          scheme: 'cursor',
          host: 'anysphere.cursor-deeplink',
          path: '/background-agent',
          queryParameters: <String, String>{'bcId': id},
        ),
      );
    }
    final (String, List<String>)? command = switch (client) {
      'claude-code' => ('claude', <String>['--resume']),
      'pi' => ('pi', <String>['--session']),
      'opencode-cli' => ('opencode', <String>['--session']),
      'antigravity-cli' => ('agy', <String>['--conversation']),
      'copilot-cli' => ('copilot', <String>['--resume']),
      'grok-build' => ('grok', <String>['--resume']),
      'gemini-cli' => ('gemini', <String>['--resume']),
      'kiro-cli' => ('kiro-cli', <String>['chat', '--resume-id']),
      'codex-cli' => ('codex', <String>['resume']),
      _ => null,
    };
    if (command == null) {
      throw const SessionLaunchException(
        'unsupported_client',
        'This client surface does not have a verified opening method.',
      );
    }
    final String id = _validSessionId(target.conversationId);
    if ((client == 'pi' || client == 'codex-cli') && !_uuid.hasMatch(id)) {
      throw const SessionLaunchException(
        'invalid_target',
        'This client requires a full UUID session ID.',
      );
    }
    final String workspace = _validWorkspace(
      target.workspacePath,
      _operatingSystem,
    );
    return LaunchPlan(
      kind: 'cli',
      executable: command.$1,
      arguments: List<String>.unmodifiable(<String>[...command.$2, id]),
      workspacePath: workspace,
    );
  }

  /// Completion means the OS accepted the launch request, not that the client
  /// logged in or resumed successfully.
  Future<void> open(
    SessionTarget target, {
    String macosTerminal = 'terminal',
    String itermOpenMode = 'new-window',
  }) async {
    final LaunchPlan plan = inspect(target);
    String executable;
    List<String> arguments;
    if (plan.kind == 'uri') {
      switch (_operatingSystem) {
        case 'macos':
          executable = '/usr/bin/open';
        case 'windows':
          executable = 'explorer.exe';
        case 'linux':
          executable = 'xdg-open';
        default:
          throw const SessionLaunchException(
            'unsupported_platform',
            'This platform cannot open a native URI.',
          );
      }
      arguments = <String>[plan.uri.toString()];
    } else {
      if (!Directory(plan.workspacePath!).existsSync()) {
        throw const SessionLaunchException(
          'workspace_missing',
          'The session workspace does not exist.',
        );
      }
      switch (_operatingSystem) {
        case 'macos':
          if (!const <String>{'terminal', 'iterm'}.contains(macosTerminal) ||
              !const <String>{
                'new-window',
                'new-tab',
              }.contains(itermOpenMode)) {
            throw const SessionLaunchException(
              'invalid_preferences',
              'Unsupported macOS terminal preference.',
            );
          }
          final String command =
              'cd -- ${_shellQuote(plan.workspacePath!)} && exec '
              '${_shellQuote(plan.executable!)} ${plan.arguments.map(_shellQuote).join(' ')}';
          executable = '/usr/bin/osascript';
          arguments = <String>[
            '-e',
            _terminalScript(command, macosTerminal, itermOpenMode),
          ];
        case 'windows':
          executable = 'wt.exe';
          arguments = <String>[
            '-d',
            plan.workspacePath!,
            plan.executable!,
            ...plan.arguments,
          ];
        default:
          throw const SessionLaunchException(
            'unsupported_platform',
            'Interactive CLI opening is not implemented for this platform.',
          );
      }
    }
    try {
      final ProcessResult result = await _processRunner(executable, arguments);
      if (result.exitCode != 0) {
        throw const SessionLaunchException(
          'launch_failed',
          'The operating system rejected the launch request.',
        );
      }
    } on SessionLaunchException {
      rethrow;
    } on Object {
      throw const SessionLaunchException(
        'launch_failed',
        'The operating system could not start the launcher.',
      );
    }
  }
}

final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
final RegExp _sessionId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]*$');

String _validSessionId(String? value) {
  final String id = (value ?? '').trim();
  if (id.isEmpty || id.length > 256 || !_sessionId.hasMatch(id)) {
    throw const SessionLaunchException(
      'invalid_target',
      'A valid session ID is required.',
    );
  }
  return id;
}

String _validWorkspace(String? value, String operatingSystem) {
  final String workspace = value ?? '';
  final bool absolute = operatingSystem == 'windows'
      ? RegExp(r'^[A-Za-z]:[\\/]').hasMatch(workspace) ||
            RegExp(r'^\\\\[^\\/]+[\\/][^\\/]+(?:[\\/]|$)').hasMatch(workspace)
      : workspace.startsWith('/');
  if (!absolute ||
      workspace != workspace.trim() ||
      workspace.length > 4096 ||
      workspace.contains(RegExp(r'[\x00\r\n]'))) {
    throw const SessionLaunchException(
      'invalid_target',
      'An absolute workspace path is required.',
    );
  }
  return workspace;
}

String _shellQuote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";
String _scriptQuote(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

String _terminalScript(String command, String terminal, String mode) {
  final String quoted = _scriptQuote(command);
  if (terminal == 'terminal') {
    return 'tell application "Terminal"\nactivate\ndo script "$quoted"\nend tell';
  }
  if (mode == 'new-tab') {
    return 'tell application "iTerm"\nactivate\nif (count of windows) = 0 then\n'
        'set newWindow to (create window with default profile)\n'
        'tell current session of newWindow to write text "$quoted"\n'
        'else\ntell current window\n'
        'set newTab to (create tab with default profile)\nend tell\n'
        'tell current session of newTab to write text "$quoted"\nend if\nend tell';
  }
  return 'tell application "iTerm"\nactivate\n'
      'set newWindow to (create window with default profile)\n'
      'tell current session of newWindow to write text "$quoted"\nend tell';
}

Future<ProcessResult> _runProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  final Process process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  final Future<void> stdoutDone = process.stdout.drain<void>();
  final Future<void> stderrDone = process.stderr.drain<void>();
  await process.stdin.close();
  final int code = await process.exitCode.timeout(
    const Duration(seconds: 5),
    onTimeout: () {
      process.kill();
      throw const SessionLaunchException(
        'launch_timeout',
        'The operating system did not accept the launch request in time.',
      );
    },
  );
  await Future.wait(<Future<void>>[stdoutDone, stderrDone]);
  return ProcessResult(process.pid, code, '', '');
}
