import 'dart:io';

import 'package:agent_session_launcher/protocol.dart';
import 'package:agent_session_launcher/agent_session_launcher.dart';
import 'package:test/test.dart';

void main() {
  test(
    'classifies a Claude Desktop hook without accepting the full environment',
    () async {
      expect(
        await handleRequest(<String, Object?>{
          'version': 1,
          'action': 'classify',
          'source': 'Claude Code',
          'claudeEntrypoint': 'claude-desktop',
        }),
        <String, Object?>{'version': 1, 'ok': true, 'client': 'claude-desktop'},
      );
    },
  );

  test('clients lists configured clients without ambiguous labels', () async {
    final result = await handleRequest(
      <String, Object?>{'version': 1, 'action': 'clients'},
      launcher: SessionLauncher(
        operatingSystem: 'macos',
        config: LauncherConfig.fromJson(<String, Object?>{
          'schemaVersion': 1,
          'clients': <String, Object?>{
            'cursor': <String, Object?>{'enabled': false},
          },
        }),
      ),
    );
    expect(result['ok'], isTrue);
    final clients = (result['clients']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(clients.map((c) => c['id']), isNot(contains('codex')));
    expect(clients.singleWhere((c) => c['id'] == 'cursor')['enabled'], isFalse);
    final rejected = await handleRequest(<String, Object?>{
      'version': 1,
      'action': 'clients',
      'filter': 'cli',
    });
    expect(
      (rejected['error']! as Map<String, Object?>)['code'],
      'invalid_request',
    );
  });

  test(
    'inspect returns an argument vector and never performs an open',
    () async {
      final result = await handleRequest(<String, Object?>{
        'version': 1,
        'action': 'inspect',
        'target': <String, Object?>{
          'client': 'pi',
          'conversationId': 'a45cce14-b0be-4aea-a8f9-e88195674770',
          'workspacePath': '/workspace',
        },
      }, launcher: SessionLauncher(operatingSystem: 'macos'));
      expect(result['ok'], isTrue);
      final plan = result['plan']! as Map<String, Object?>;
      expect(plan['kind'], 'cli');
      expect(plan['executable'], 'pi');
      expect(plan['arguments'], <String>[
        '--session',
        'a45cce14-b0be-4aea-a8f9-e88195674770',
      ]);
    },
  );

  test(
    'protocol rejects arbitrary executable, URL and unknown fields',
    () async {
      for (final target in <Map<String, Object?>>[
        <String, Object?>{'client': 'pi', 'command': 'touch /tmp/no'},
        <String, Object?>{'client': 'pi', 'uri': 'file:///tmp/no'},
      ]) {
        final result = await handleRequest(<String, Object?>{
          'version': 1,
          'action': 'inspect',
          'target': target,
        });
        expect(result['ok'], isFalse);
        expect(
          (result['error']! as Map<String, Object?>)['code'],
          'invalid_request',
        );
      }
    },
  );

  test('unsupported source or invalid request fails closed', () async {
    final ambiguous = await handleRequest(<String, Object?>{
      'version': 1,
      'action': 'inspect',
      'target': <String, Object?>{
        'client': 'opencode',
        'conversationId': 'ses_123',
        'workspacePath': '/workspace',
      },
    });
    expect(ambiguous['ok'], isFalse);
    expect(
      (ambiguous['error']! as Map<String, Object?>)['code'],
      'unsupported_client',
    );
    final invalid = await handleRequest(<String, Object?>{
      'version': 2,
      'action': 'inspect',
    });
    expect(invalid['ok'], isFalse);
    expect(
      (invalid['error']! as Map<String, Object?>)['code'],
      'invalid_request',
    );
  });

  test('rejects invalid terminal preferences during inspection', () async {
    final result = await handleRequest(<String, Object?>{
      'version': 1,
      'action': 'inspect',
      'target': <String, Object?>{
        'client': 'codex-desktop',
        'conversationId': 'a45cce14-b0be-4aea-a8f9-e88195674770',
      },
      'preferences': <String, Object?>{'macosTerminal': 'custom-command'},
    });
    expect(result['ok'], isFalse);
    expect(
      (result['error']! as Map<String, Object?>)['code'],
      'invalid_preferences',
    );
  });

  test('explicit null fields are rejected by the documented schema', () async {
    final targetNull = await handleRequest(<String, Object?>{
      'version': 1,
      'action': 'inspect',
      'target': <String, Object?>{'client': 'pi', 'conversationId': null},
    });
    expect(
      (targetNull['error']! as Map<String, Object?>)['code'],
      'invalid_request',
    );
    final preferencesNull = await handleRequest(<String, Object?>{
      'version': 1,
      'action': 'inspect',
      'target': <String, Object?>{
        'client': 'codex-desktop',
        'conversationId': 'a45cce14-b0be-4aea-a8f9-e88195674770',
      },
      'preferences': null,
    });
    expect(
      (preferencesNull['error']! as Map<String, Object?>)['code'],
      'invalid_request',
    );
  });

  test(
    'open calls the host launcher only when requested and reports failure',
    () async {
      var calls = 0;
      final launcher = SessionLauncher(
        operatingSystem: 'macos',
        processRunner: (executable, args, {workingDirectory}) async {
          calls += 1;
          return ProcessResult(1, 1, '', '');
        },
      );
      final request = <String, Object?>{
        'version': 1,
        'action': 'inspect',
        'target': <String, Object?>{
          'client': 'claude-desktop',
          'hostSessionId': 'local_example',
        },
      };
      final inspected = await handleRequest(request, launcher: launcher);
      expect(inspected['ok'], isTrue);
      expect(calls, 0);
      request['action'] = 'open';
      final opened = await handleRequest(request, launcher: launcher);
      expect(
        (opened['error']! as Map<String, Object?>)['code'],
        'launch_failed',
      );
      expect(calls, 1);
    },
  );
}
