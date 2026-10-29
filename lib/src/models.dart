import 'dart:io';

/// A process invocation accepts an argument vector, never a caller-provided shell command.
typedef ProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

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
  });
  final String kind;
  final Uri? uri;
  final String? executable;
  final List<String> arguments;
  final String? workspacePath;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    if (uri != null) 'uri': uri.toString(),
    if (executable != null) 'executable': executable,
    if (kind == 'cli') 'arguments': arguments,
    if (workspacePath != null) 'workspacePath': workspacePath,
  };
}

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
  });

  final String id;
  final String name;
  final bool enabled;
  final bool builtin;

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
  };
}
