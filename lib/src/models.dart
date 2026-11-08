import 'dart:io';

/// A process invocation accepts an argument vector, never a caller-provided shell command.
typedef ProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

/// Starts a program that keeps running on its own, such as a Linux terminal
/// window; completion means it started.
typedef DetachedStarter =
    Future<void> Function(String executable, List<String> arguments);

final class SessionTarget {
  const SessionTarget({
    required this.client,
    this.conversationId,
    this.workspacePath,
    this.hostSessionId,
  });

  final String client;
  final String? conversationId;
  final String? workspacePath;
  final String? hostSessionId;
}

/// A new session or conversation in [client], optionally with a [prompt].
///
/// The prompt is data for the client, never a command: each opener passes it
/// as one argument or one URI query value. What the client then does with it
/// is its [NewSessionInfo.prompt] (`prefill` or `send`).
final class NewSessionTarget {
  const NewSessionTarget({
    required this.client,
    this.prompt,
    this.workspacePath,
    this.environment,
  });

  final String client;
  final String? prompt;

  /// Where a CLI starts; the home directory when null. Unused for URIs.
  final String? workspacePath;

  /// [RunEnvironment.wsl]: on Windows, the CLI is installed in the default
  /// WSL distribution and runs there. Null runs it on this system.
  final String? environment;
}

/// The values of [NewSessionTarget.environment].
abstract final class RunEnvironment {
  /// The default distribution of Windows Subsystem for Linux, through
  /// `wsl.exe --cd <dir> --exec bash -lic ...`, so the person's shell profile
  /// puts the client on PATH.
  static const String wsl = 'wsl';
}

/// What a client does with the prompt of a new session.
abstract final class PromptHandling {
  /// The prompt waits in the composer until the person sends it.
  static const String prefill = 'prefill';

  /// The client submits the prompt as the session's first message.
  static const String send = 'send';

  static const Set<String> values = <String>{prefill, send};
}

final class SessionLaunchException implements Exception {
  const SessionLaunchException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => '$code: $message';
}

/// A fixed launch instruction, not a caller-supplied command.
final class LaunchPlan {
  const LaunchPlan({
    required this.kind,
    this.uri,
    this.executable,
    this.arguments = const <String>[],
    this.workspacePath,
    this.opener,
    this.newSession = false,
    this.prompt,
    this.environment,
  });
  final String kind;
  final Uri? uri;
  final String? executable;
  final List<String> arguments;
  final String? workspacePath;

  /// How a CLI plan is opened: on Windows [WindowsOpener.windowsTerminal]
  /// when `wt.exe` is on PATH, otherwise [WindowsOpener.powershell]; on Linux
  /// the terminal program found (one of [linuxTerminalPrograms]). Null on
  /// macOS and for URI plans.
  final String? opener;

  /// The plan starts a new session instead of resuming one.
  final bool newSession;

  /// For a new session that carries a prompt: what the client does with it
  /// ([PromptHandling]). Null when there is no prompt.
  final String? prompt;

  /// [RunEnvironment.wsl] when [executable] is `wsl.exe` running the client
  /// inside WSL; null otherwise.
  final String? environment;

  LaunchPlan withOpener(String? value) => LaunchPlan(
    kind: kind,
    uri: uri,
    executable: executable,
    arguments: arguments,
    workspacePath: workspacePath,
    opener: value,
    newSession: newSession,
    prompt: prompt,
    environment: environment,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    if (uri != null) 'uri': uri.toString(),
    if (executable != null) 'executable': executable,
    if (kind == 'cli') 'arguments': arguments,
    if (workspacePath != null) 'workspacePath': workspacePath,
    if (opener != null) 'opener': opener,
    if (newSession) 'newSession': true,
    if (prompt != null) 'prompt': prompt,
    if (environment != null) 'environment': environment,
  };
}

/// The Linux terminal programs tried in order for a CLI plan. Each takes the
/// command as an argument vector, never as shell text.
/// `x-terminal-emulator` is the system default on Debian and Ubuntu.
const List<String> linuxTerminalPrograms = <String>[
  'x-terminal-emulator',
  'gnome-terminal',
  'konsole',
  'xfce4-terminal',
  'kitty',
  'alacritty',
  'wezterm',
  'foot',
  'xterm',
];

/// The values of [LaunchPlan.opener].
abstract final class WindowsOpener {
  /// Windows Terminal (`wt.exe -d <workspace> <program> <args>`).
  static const String windowsTerminal = 'windows-terminal';

  /// A new console window from Windows PowerShell's `Start-Process`, used
  /// when Windows Terminal is not installed.
  static const String powershell = 'powershell';
}

/// Whether a program named like `wt.exe` can be started by name.
typedef CommandLookup = bool Function(String command);

enum MacosTerminal {
  terminal('terminal'),
  iterm('iterm');

  const MacosTerminal(this.value);
  final String value;
}

enum ITermOpenMode {
  newWindow('new-window'),
  newTab('new-tab');

  const ITermOpenMode(this.value);
  final String value;
}

/// How an interactive CLI session is opened. Unset fields fall back, in order,
/// to the client's configuration, the host configuration and built-in defaults.
final class LaunchPreferences {
  const LaunchPreferences({this.macosTerminal, this.itermOpenMode});

  /// Parses the `preferences` object shared by requests and configuration.
  factory LaunchPreferences.fromJson(
    Object? value, {
    String path = 'preferences',
    String code = 'invalid_preferences',
  }) {
    Never fail(String reason) =>
        throw SessionLaunchException(code, '$path: $reason');
    if (value is! Map<String, Object?>) fail('must be an object.');
    for (final String key in value.keys) {
      if (key != 'macosTerminal' && key != 'itermOpenMode') {
        fail('unsupported field "$key".');
      }
    }
    MacosTerminal? terminal;
    if (value.containsKey('macosTerminal')) {
      terminal =
          MacosTerminal.values
              .where((t) => t.value == value['macosTerminal'])
              .firstOrNull ??
          fail('macosTerminal must be "terminal" or "iterm".');
    }
    ITermOpenMode? mode;
    if (value.containsKey('itermOpenMode')) {
      mode =
          ITermOpenMode.values
              .where((m) => m.value == value['itermOpenMode'])
              .firstOrNull ??
          fail('itermOpenMode must be "new-window" or "new-tab".');
    }
    return LaunchPreferences(macosTerminal: terminal, itermOpenMode: mode);
  }

  final MacosTerminal? macosTerminal;
  final ITermOpenMode? itermOpenMode;

  /// Returns these preferences with unset fields taken from [fallback].
  LaunchPreferences over(LaunchPreferences? fallback) => LaunchPreferences(
    macosTerminal: macosTerminal ?? fallback?.macosTerminal,
    itermOpenMode: itermOpenMode ?? fallback?.itermOpenMode,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    if (macosTerminal != null) 'macosTerminal': macosTerminal!.value,
    if (itermOpenMode != null) 'itermOpenMode': itermOpenMode!.value,
  };
}

/// A host-facing summary of one client, suitable for a settings screen.
final class ClientInfo {
  const ClientInfo({
    required this.id,
    required this.name,
    required this.enabled,
    required this.builtin,
    required this.openSupported,
    this.origin = 'builtin',
    this.extensionFile,
    this.kind,
    this.idSource,
    this.idFormat,
    this.newSession,
  });

  final String id;
  final String name;
  final bool enabled;
  final bool builtin;

  /// How a new session opens, or null without a verified way.
  final NewSessionInfo? newSession;

  /// Where the client was first defined: `builtin`, `extension` or `host`.
  final String origin;

  /// The user extension file that defines or customizes this client.
  final String? extensionFile;

  /// `cli`, `uri`, or null for an identity without a verified opening method.
  final String? kind;
  final String? idSource;
  final String? idFormat;

  /// The platform has an opener for [kind]; it does not prove the app exists.
  final bool openSupported;

  bool get requiresWorkspace => kind == 'cli';

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'enabled': enabled,
    'builtin': builtin,
    'origin': origin,
    if (extensionFile != null) 'extensionFile': extensionFile,
    'kind': kind,
    if (idSource != null) 'idSource': idSource,
    if (idFormat != null) 'idFormat': idFormat,
    'requiresWorkspace': requiresWorkspace,
    'openSupported': openSupported,
    'newSession': newSession?.toJson(),
  };
}

/// A client's verified way to open a new session.
final class NewSessionInfo {
  const NewSessionInfo({
    required this.kind,
    required this.prompt,
    required this.openSupported,
  });

  /// `cli` or `uri`.
  final String kind;

  /// [PromptHandling.prefill] or [PromptHandling.send]; null when this way
  /// takes no prompt.
  final String? prompt;

  /// The platform has an opener for [kind]; it does not prove the app exists.
  final bool openSupported;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'prompt': prompt,
    'openSupported': openSupported,
  };
}
