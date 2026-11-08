import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// Whether this package implements an opener for a plan kind on [os].
bool supportsOpeningOn(String os, String kind) =>
    const <String>{'macos', 'windows', 'linux'}.contains(os) &&
    (kind == 'uri' || kind == 'cli');

/// Hands a validated plan to the operating system.
Future<void> openPlan(
  LaunchPlan plan, {
  required String operatingSystem,
  required LaunchPreferences preferences,
  required ProcessRunner processRunner,
  DetachedStarter detachedStarter = startDetached,
}) async {
  String executable;
  List<String> arguments;
  if (plan.kind == 'uri') {
    switch (operatingSystem) {
      case 'macos':
        executable = '/usr/bin/open';
      case 'windows':
        executable = 'powershell.exe';
      case 'linux':
        executable = 'xdg-open';
      default:
        throw const SessionLaunchException(
          'unsupported_platform',
          'This platform cannot open a native URI.',
        );
    }
    arguments = operatingSystem == 'windows'
        ? <String>[
            '-NoProfile',
            '-NonInteractive',
            '-Command',
            windowsShellExecuteScript(plan.uri.toString()),
          ]
        : <String>[plan.uri.toString()];
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
      case 'windows' when plan.newSession:
        // A new session's prompt is free text. It never travels through
        // Windows Terminal's or PowerShell's own argument parsing: the whole
        // launch is one Base64 script (see [windowsNewSessionScript]).
        final List<String> host = <String>[
          '-NoLogo',
          '-NoProfile',
          '-EncodedCommand',
          encodePowerShellCommand(windowsNewSessionScript(plan)),
        ];
        if (host.last.length > _maxEncodedCommand) {
          throw const SessionLaunchException(
            'invalid_prompt',
            'The prompt is too long for a Windows command line.',
          );
        }
        if (plan.opener == WindowsOpener.powershell) {
          executable = 'powershell.exe';
          arguments = <String>[
            '-NoProfile',
            '-NonInteractive',
            '-Command',
            windowsStartProcessScript(
              LaunchPlan(
                kind: 'cli',
                executable: 'powershell.exe',
                arguments: host,
                workspacePath: plan.workspacePath,
              ),
            ),
          ];
        } else {
          executable = 'wt.exe';
          arguments = <String>['powershell.exe', ...host];
        }
      case 'windows' when plan.opener == WindowsOpener.powershell:
        executable = 'powershell.exe';
        arguments = <String>[
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          windowsStartProcessScript(plan),
        ];
      case 'windows':
        executable = 'wt.exe';
        arguments = <String>[
          '-d',
          plan.workspacePath!,
          plan.executable!,
          ...plan.arguments,
        ];
      case 'linux':
        final String? terminal = plan.opener;
        if (terminal == null) {
          throw const SessionLaunchException(
            'unsupported_platform',
            'No supported terminal program was found.',
          );
        }
        try {
          await detachedStarter(terminal, linuxTerminalArguments(plan));
        } on Object {
          throw const SessionLaunchException(
            'launch_failed',
            'The operating system could not start the terminal.',
          );
        }
        return;
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

/// Windows' command line holds 32,767 characters; this leaves room for the
/// opener's own arguments.
const int _maxEncodedCommand = 32000;

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

/// The arguments of [LaunchPlan.opener] on Linux. The terminal runs `sh`,
/// which changes to the workspace and then replaces itself with the client;
/// the workspace, program and arguments are positional parameters, never
/// part of the shell text.
List<String> linuxTerminalArguments(LaunchPlan plan) {
  final List<String> command = <String>[
    'sh',
    '-c',
    'unset ${parentSessionVariables.join(' ')}; '
        r'cd -- "$1" && shift && exec "$@"',
    'sh',
    plan.workspacePath!,
    plan.executable!,
    ...plan.arguments,
  ];
  return switch (plan.opener) {
    'gnome-terminal' => <String>['--', ...command],
    'xfce4-terminal' => <String>['-x', ...command],
    'wezterm' => <String>['start', '--', ...command],
    'kitty' || 'foot' => command,
    // x-terminal-emulator (Debian policy), konsole, alacritty and xterm.
    _ => <String>['-e', ...command],
  };
}

/// Variables a running Agent session sets for its own child processes. A
/// session opened from such a process (for example a host started by a
/// Claude Code hook) would otherwise take itself for a child session:
/// Claude Code turns off transcript saving when it inherits
/// `CLAUDE_CODE_CHILD_SESSION`. New sessions on Windows and every Linux
/// terminal start without them; macOS Terminal and iTerm start a fresh login
/// shell.
const List<String> parentSessionVariables = <String>[
  'CLAUDECODE',
  'CLAUDE_CODE_ENTRYPOINT',
  'CLAUDE_CODE_CHILD_SESSION',
  'CLAUDE_CODE_SSE_PORT',
  'CODEX_THREAD_ID',
  'CODEX_SANDBOX',
  'CODEX_SANDBOX_NETWORK_DISABLED',
];

/// Runs a CLI plan inside the default WSL distribution. `bash -lic` reads
/// the person's profile, which is where installers put clients on PATH; the
/// program and its arguments are bash's positional parameters, never shell
/// text. A `~/` program is expanded inside WSL.
LaunchPlan wslPlan(
  LaunchPlan plan, {
  required String? linuxDirectory,
  required String windowsDirectory,
}) => LaunchPlan(
  kind: 'cli',
  executable: 'wsl.exe',
  arguments: List<String>.unmodifiable(<String>[
    '--cd',
    linuxDirectory ?? '~',
    '--exec',
    'bash',
    '-lic',
    r'p=$0; case $p in "~/"*) p=$HOME/${p#"~/"};; esac; exec "$p" "$@"',
    plan.executable!,
    ...plan.arguments,
  ]),
  workspacePath: windowsDirectory,
  newSession: plan.newSession,
  prompt: plan.prompt,
  environment: RunEnvironment.wsl,
);

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

/// Starts a program that keeps running after this process exits.
Future<void> startDetached(String executable, List<String> arguments) async {
  await Process.start(executable, arguments, mode: ProcessStartMode.detached);
}

/// The Windows PowerShell script that opens a CLI plan in a new console
/// window when Windows Terminal is missing. Every value is a single-quoted
/// literal, so nothing in it is expanded; `ProcessStartInfo` is used instead
/// of `Start-Process` because the latter treats `[` and `]` in the working
/// directory as wildcards. Arguments are already restricted to plain tokens.
String windowsStartProcessScript(LaunchPlan plan) => <String>[
  r"$ErrorActionPreference = 'Stop'",
  r'$info = New-Object System.Diagnostics.ProcessStartInfo',
  '\$info.FileName = ${_powershellQuote(plan.executable!)}',
  '\$info.Arguments = ${_powershellQuote(plan.arguments.join(' '))}',
  '\$info.WorkingDirectory = ${_powershellQuote(plan.workspacePath!)}',
  r'$info.UseShellExecute = $true',
  r'[void][System.Diagnostics.Process]::Start($info)',
].join('; ');

/// Opens a URI on Windows the way a click does: `ShellExecute` through
/// `System.Diagnostics.Process` with the URI as a single-quoted literal.
/// `explorer.exe <uri>` is not used: for some registered app schemes
/// (`codex://` and `cursor://` links with a query, seen on Windows 11) it
/// opens the Documents folder instead of the app. A scheme without a handler
/// fails the call, which reports `launch_failed`.
String windowsShellExecuteScript(String uri) => <String>[
  r"$ErrorActionPreference = 'Stop'",
  r'$info = New-Object System.Diagnostics.ProcessStartInfo',
  '\$info.FileName = ${_powershellQuote(uri)}',
  r'$info.UseShellExecute = $true',
  r'[void][System.Diagnostics.Process]::Start($info)',
].join('; ');

/// The script a new-session terminal runs on Windows, passed as
/// `-EncodedCommand` so neither Windows Terminal (which splits on `;`) nor
/// PowerShell's native-argument passing ever parses the prompt. It finds the
/// program on PATH, starts it in the console with a command line built by
/// [windowsArgument] (or, for an npm-style `.cmd` shim, by
/// [windowsBatchArgument] through `cmd.exe`), waits for it and passes on its
/// exit code. When the program is missing it says so and waits for Enter.
String windowsNewSessionScript(LaunchPlan plan) => <String>[
  r"$ErrorActionPreference = 'Stop'",
  'try {',
  '  \$name = ${_powershellQuote(plan.executable!)}',
  r'  $command = Get-Command -Name $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1',
  r"  if ($null -eq $command) { throw ($name + ' was not found on PATH.') }",
  r'  $path = $command.Source',
  r'  $info = New-Object System.Diagnostics.ProcessStartInfo',
  r"  if ($path -match '\.(cmd|bat)$') {",
  r'    $shell = $env:ComSpec',
  r"    if (-not $shell) { $shell = Join-Path $env:SystemRoot 'System32\cmd.exe' }",
  r'    $info.FileName = $shell',
  "    \$info.Arguments = '/e:ON /v:OFF /d /c \"\"' + \$path + '\" ' + "
      "${_powershellQuote(plan.arguments.map(windowsBatchArgument).join(' '))} + '\"'",
  '  } else {',
  r'    $info.FileName = $path',
  '    \$info.Arguments = '
      '${_powershellQuote(plan.arguments.map(windowsArgument).join(' '))}',
  '  }',
  '  \$info.WorkingDirectory = ${_powershellQuote(plan.workspacePath!)}',
  r'  $info.UseShellExecute = $false',
  '  foreach (\$variable in @(${parentSessionVariables.map(_powershellQuote).join(', ')})) '
      r'{ $info.EnvironmentVariables.Remove($variable) }',
  r'  $process = [System.Diagnostics.Process]::Start($info)',
  r'  $process.WaitForExit()',
  r'  exit $process.ExitCode',
  '} catch {',
  r'  Write-Host $_.Exception.Message',
  r"  [void](Read-Host 'Press Enter to close')",
  '  exit 1',
  '}',
].join('\n');

/// `-EncodedCommand`'s format: Base64 of the script's UTF-16LE bytes.
String encodePowerShellCommand(String script) {
  final List<int> bytes = <int>[];
  for (final int unit in script.codeUnits) {
    bytes
      ..add(unit & 0xff)
      ..add(unit >> 8);
  }
  return base64.encode(bytes);
}

/// One argument as the Microsoft C runtime (and `CommandLineToArgvW`) splits
/// a command line back into arguments: quoted when it has whitespace or a
/// quote, with `\` doubled only before a `"`.
String windowsArgument(String value) {
  if (value.isNotEmpty && !value.contains(RegExp(r'[\s"]'))) return value;
  final StringBuffer out = StringBuffer('"');
  int backslashes = 0;
  for (final int unit in value.codeUnits) {
    if (unit == 0x5C) {
      backslashes++;
      continue;
    }
    if (unit == 0x22) {
      out.write(r'\' * (backslashes * 2 + 1));
    } else {
      out.write(r'\' * backslashes);
    }
    backslashes = 0;
    out.writeCharCode(unit);
  }
  out
    ..write(r'\' * (backslashes * 2))
    ..write('"');
  return out.toString();
}

/// One argument for a batch file run as `cmd.exe /d /c "<file> <args>"`,
/// the way Rust's standard library does it since CVE-2024-24576: always
/// quoted, a `"` doubled (cmd.exe keeps quoting balanced; the C runtime
/// reads `""` inside quotes as one `"`), a `%` written as `%%cd:~,%` so no
/// `%name%` is expanded, and `\` doubled only before a quote. cmd.exe ends a
/// command at a line break, so line breaks become spaces here.
String windowsBatchArgument(String value) {
  final String text = value.replaceAll(RegExp(r'\r\n|\r|\n'), ' ');
  final StringBuffer out = StringBuffer('"');
  int backslashes = 0;
  for (final int unit in text.codeUnits) {
    if (unit == 0x5C) {
      backslashes++;
      continue;
    }
    out.write(r'\' * (unit == 0x22 ? backslashes * 2 : backslashes));
    backslashes = 0;
    if (unit == 0x22) {
      out.write('""');
    } else if (unit == 0x25) {
      out.write('%%cd:~,%');
    } else {
      out.writeCharCode(unit);
    }
  }
  out
    ..write(r'\' * (backslashes * 2))
    ..write('"');
  return out.toString();
}

/// PowerShell treats the typographic single quotes like `'`, so all of them
/// are doubled inside a single-quoted string.
String _powershellQuote(String value) =>
    "'${value.replaceAllMapped(_singleQuotes, (m) => '${m[0]}${m[0]}')}'";

final RegExp _singleQuotes = RegExp("['\\u2018\\u2019\\u201A\\u201B]");

/// Whether [command] is a file in one of the PATH directories. App execution
/// aliases such as `wt.exe` are reparse points, so links count as present.
bool isOnPath(String command) {
  final Map<String, String> env = Platform.environment;
  final String path = env['PATH'] ?? env['Path'] ?? '';
  final String separator = Platform.isWindows ? ';' : ':';
  for (final String directory in path.split(separator)) {
    if (directory.trim().isEmpty) continue;
    final String candidate =
        '${directory.replaceAll(RegExp(r'[\/]+$'), '')}'
        '${Platform.pathSeparator}$command';
    if (FileSystemEntity.typeSync(candidate, followLinks: false) !=
        FileSystemEntityType.notFound) {
      return true;
    }
  }
  return false;
}
