import 'dart:convert';
import 'dart:io';

import 'package:agent_session_launcher/protocol.dart';

Future<void> main() async {
  Map<String, Object?> result;
  try {
    final List<int> bytes = <int>[];
    await for (final List<int> chunk in stdin) {
      if (bytes.length + chunk.length > 65536)
        throw const FormatException('Request too large.');
      bytes.addAll(chunk);
    }
    result = await handleRequest(jsonDecode(utf8.decode(bytes)));
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
