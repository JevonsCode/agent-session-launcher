import 'dart:convert';
import 'dart:io';

import 'package:agent_session_launcher/agent_session_launcher.dart';
import 'package:agent_session_launcher/protocol.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty && arguments.first == 'check') {
    exitCode = _check(arguments.sublist(1));
    return;
  }
  Map<String, Object?> result;
  try {
    final LauncherConfig config = _config(arguments);
    final List<int> bytes = <int>[];
    await for (final List<int> chunk in stdin) {
      if (bytes.length + chunk.length > 65536) {
        throw const FormatException('Request too large.');
      }
      bytes.addAll(chunk);
    }
    result = await handleRequest(
      jsonDecode(utf8.decode(bytes)),
      launcher: SessionLauncher(config: config),
    );
  } on SessionLaunchException catch (error) {
    result = <String, Object?>{
      'version': 1,
      'ok': false,
      'error': <String, Object?>{'code': error.code, 'message': error.message},
    };
  } on Object {
    result = <String, Object?>{
      'version': 1,
      'ok': false,
      'error': <String, Object?>{
        'code': 'invalid_request',
        'message': 'Input must be a bounded UTF-8 JSON request.',
      },
    };
  }
  stdout.writeln(jsonEncode(result));
  if (result['ok'] != true) exitCode = 1;
}

/// Reads the host's trusted configuration file and the user's extension
/// directory on every invocation.
LauncherConfig _config(List<String> arguments) {
  String? configPath;
  String? extensionsPath;
  bool valid = arguments.length.isEven && arguments.length <= 4;
  for (int i = 0; valid && i < arguments.length; i += 2) {
    final String value = arguments[i + 1];
    valid = File(value).isAbsolute;
    if (arguments[i] == '--config' && configPath == null) {
      configPath = value;
    } else if (arguments[i] == '--extensions' && extensionsPath == null) {
      extensionsPath = value;
    } else {
      valid = false;
    }
  }
  if (!valid) {
    throw const SessionLaunchException(
      'invalid_configuration',
      'Expected [--config <absolute file>] [--extensions <absolute directory>].',
    );
  }
  return LauncherConfig.load(
    hostConfig: configPath == null ? null : _readHostConfig(configPath),
    extensionsDirectory: extensionsPath,
  );
}

String _readHostConfig(String path) {
  try {
    final file = File(path).openSync();
    List<int> bytes;
    try {
      bytes = file.readSync(65537);
    } finally {
      file.closeSync();
    }
    if (bytes.length > 65536) throw const FormatException();
    return utf8.decode(bytes);
  } on Object {
    throw const SessionLaunchException(
      'invalid_configuration',
      'The trusted configuration file could not be read.',
    );
  }
}

/// `check <file>`: validates one extension file against the built-in catalog
/// for someone writing it by hand. Conflicts with sibling files are reported
/// by the host's client list.
int _check(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('Usage: agent-session-launcher check <client-id>.json');
    return 64;
  }
  final ExtensionFile file = readExtensionFile(arguments.single);
  final LauncherConfig config = LauncherConfig.fromJson(
    const <String, Object?>{'schemaVersion': 1},
    extensions: <ExtensionFile>[file],
  );
  if (config.extensionErrors.isNotEmpty) {
    for (final ExtensionProblem problem in config.extensionErrors) {
      stdout.writeln('${problem.file}: ${problem.message}');
    }
    return 1;
  }
  final ClientInfo client = SessionLauncher(
    config: config,
  ).clients().firstWhere((c) => c.extensionFile == file.name);
  stdout.writeln('${file.name}: OK');
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(client.toJson()));
  return 0;
}
