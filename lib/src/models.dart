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
