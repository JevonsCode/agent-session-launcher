import 'dart:io';

import 'models.dart';

/// Whether this package implements an opener for a plan kind on [os].
bool supportsOpeningOn(String os, String kind) => kind == 'uri'
    ? const <String>{'macos', 'windows', 'linux'}.contains(os)
    : const <String>{'macos', 'windows'}.contains(os);

/// Hands a validated plan to the operating system.
Future<void> openPlan(
  LaunchPlan plan, {
  required String operatingSystem,
  required LaunchPreferences preferences,
  required ProcessRunner processRunner,
}) async {
  String executable;
  List<String> arguments;
  if (plan.kind == 'uri') {
    switch (operatingSystem) {
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
    switch (operatingSystem) {
      case 'macos':
        final String command =
            'cd -- ${_shellQuote(plan.workspacePath!)} && exec '
            '${_shellQuote(plan.executable!)} ${plan.arguments.map(_shellQuote).join(' ')}';
        executable = '/usr/bin/osascript';
        arguments = <String>[
          '-e',
          _terminalScript(
            command,
            preferences.macosTerminal ?? MacosTerminal.terminal,
            preferences.itermOpenMode ?? ITermOpenMode.newWindow,
          ),
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
    final ProcessResult result = await processRunner(executable, arguments);
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

String _shellQuote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";
String _scriptQuote(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

String _terminalScript(
  String command,
  MacosTerminal terminal,
  ITermOpenMode mode,
) {
  final String quoted = _scriptQuote(command);
  if (terminal == MacosTerminal.terminal) {
    return 'tell application "Terminal"\nactivate\ndo script "$quoted"\nend tell';
  }
  if (mode == ITermOpenMode.newTab) {
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

Future<ProcessResult> runProcess(
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
