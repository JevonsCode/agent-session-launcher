import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

Future<Map<String, Object?>> callWithConfig(
  String configPath,
  Map<String, Object?> request,
) async {
  final process = await Process.start(Platform.resolvedExecutable, <String>[
    'run',
    'bin/agent_session_launcher.dart',
    '--config',
    configPath,
  ]);
  process.stdin.write(jsonEncode(request));
  await process.stdin.close();
  final output = await utf8.decoder.bind(process.stdout).join();
  await process.stderr.drain<void>();
  await process.exitCode;
  return jsonDecode(output) as Map<String, Object?>;
}

void main() {
  test(
    'a local profile adds a client without replacing built-in clients',
    () async {
      final temp = await Directory.systemTemp.createTemp('launcher-profile-');
      addTearDown(() => temp.delete(recursive: true));
      final config = File('${temp.path}/agents.json');
      await config.writeAsString(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'clients': <String, Object?>{
            'example-cli': <String, Object?>{
              'aliases': <String>['Example CLI'],
              'launch': <String, Object?>{
                'command': <String>['example', '--resume', '{id}'],
              },
            },
          },
        }),
      );

      final custom = await callWithConfig(config.path, <String, Object?>{
        'version': 1,
        'action': 'classify',
        'source': 'Example CLI',
      });
      expect(custom['client'], 'example-cli');
      final inspected = await callWithConfig(config.path, <String, Object?>{
        'version': 1,
        'action': 'inspect',
        'target': <String, Object?>{
          'client': 'example-cli',
          'conversationId': 'session-42',
          'workspacePath': Platform.isWindows ? r'C:\workspace' : '/workspace',
        },
      });
      expect(inspected['ok'], true);
      final plan = inspected['plan']! as Map<String, Object?>;
      expect(plan['executable'], 'example');
      expect(plan['arguments'], <String>['--resume', 'session-42']);
      final builtin = await callWithConfig(config.path, <String, Object?>{
        'version': 1,
        'action': 'classify',
        'source': 'Claude Code',
        'claudeEntrypoint': 'claude-desktop',
      });
      expect(builtin['client'], 'claude-desktop');
    },
  );
  test(
    'bad configuration fails closed and cannot be provided in a request',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'launcher-bad-config-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final config = File('${temp.path}/agents.json');
      await config.writeAsString('{bad json');
      final failed = await callWithConfig(config.path, <String, Object?>{
        'version': 1,
        'action': 'classify',
        'source': 'Pi',
      });
      expect(
        (failed['error']! as Map<String, Object?>)['code'],
        'invalid_configuration',
      );
      await config.writeAsString(
        '{"schemaVersion":1,"clients":{"pi":{"launch":{"command":["pi","{id}"],"idFormat":"safe"}}}}',
      );
      final weakened = await callWithConfig(config.path, <String, Object?>{
        'version': 1,
        'action': 'classify',
        'source': 'Pi',
      });
      expect(
        (weakened['error']! as Map<String, Object?>)['message'],
        r'$.clients.pi.launch.idFormat: must stay uuid for this client.',
      );
      await config.writeAsString('{"schemaVersion":1,"clients":{}}');
      final injected = await callWithConfig(config.path, <String, Object?>{
        'version': 1,
        'action': 'classify',
        'source': 'Pi',
        'configPath': '/tmp/unsafe',
      });
      expect(
        (injected['error']! as Map<String, Object?>)['code'],
        'invalid_request',
      );
    },
  );
}
