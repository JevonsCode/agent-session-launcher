import 'dart:convert';
import 'dart:io';

import 'package:agent_session_launcher/agent_session_launcher.dart';
import 'package:agent_session_launcher/protocol.dart';

Future<void> main(List<String> arguments) async {
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

/// Reads the host's trusted configuration file on every invocation.
LauncherConfig _config(List<String> arguments) {
  if (arguments.isEmpty) return LauncherConfig.defaults;
  String text;
  try {
    if (arguments.length != 2 ||
        arguments[0] != '--config' ||
        !File(arguments[1]).isAbsolute) {
      throw const FormatException();
    }
    final file = File(arguments[1]).openSync();
    List<int> bytes;
    try {
      bytes = file.readSync(65537);
    } finally {
      file.closeSync();
    }
    if (bytes.length > 65536) throw const FormatException();
    text = utf8.decode(bytes);
  } on Object {
    throw const SessionLaunchException(
      'invalid_configuration',
      'The trusted configuration file could not be read.',
    );
  }
  return LauncherConfig.decode(text);
}
