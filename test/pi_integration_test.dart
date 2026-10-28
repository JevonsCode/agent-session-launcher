import 'dart:convert';
import 'dart:io';

import 'package:agent_session_launcher/agent_session_launcher.dart';
import 'package:test/test.dart';

void main() {
  final String? pi = Platform.environment['PI_EXECUTABLE'];
  test(
    'Pi resolves the launcher plan to the same isolated session',
    () async {
      final Directory temp = await Directory.systemTemp.createTemp(
        'agent-session-pi-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final Directory workspace = Directory('${temp.path}/project')
        ..createSync();
      final Directory agent = Directory('${temp.path}/agent')..createSync();
      const String id = '7c129541-3a71-4162-b501-31e9a0c2c63d';
      Future<Map<String, Object?>> state(List<String> args) async {
        final Process process = await Process.start(
          pi!,
          <String>[
            '--mode',
            'rpc',
            '--offline',
            '--no-extensions',
            '--no-skills',
            '--no-context-files',
            ...args,
          ],
          workingDirectory: workspace.path,
          environment: <String, String>{
            'PATH': Platform.environment['PATH'] ?? '',
            'PI_CODING_AGENT_DIR': agent.path,
            'PI_OFFLINE': '1',
          },
          includeParentEnvironment: false,
        );
        process.stdin.writeln(
          jsonEncode(<String, String>{'type': 'get_state'}),
        );
        await process.stdin.close();
        final Future<String> out = utf8.decoder.bind(process.stdout).join();
        final Future<String> err = utf8.decoder.bind(process.stderr).join();
        final int exit = await process.exitCode.timeout(
          const Duration(seconds: 20),
          onTimeout: () {
            process.kill();
            throw StateError('Pi RPC timed out.');
          },
        );
        final String stdout = await out;
        final String stderr = await err;
        expect(exit, 0, reason: stderr);
        final Map<String, Object?> response = stdout
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .map((line) => jsonDecode(line) as Map<String, Object?>)
            .firstWhere((row) => row['command'] == 'get_state');
        expect(response['success'], isTrue);
        return response['data']! as Map<String, Object?>;
      }

      final Map<String, Object?> initial = await state(<String>[
        '--session-id',
        id,
      ]);
      final File session = File(initial['sessionFile']! as String);
      expect(
        session.path.startsWith('${temp.path}${Platform.pathSeparator}'),
        isTrue,
      );
      await session.parent.create(recursive: true);
      await session.writeAsString(
        '${jsonEncode(<String, Object?>{'type': 'session', 'version': 3, 'id': id, 'timestamp': '2026-01-01T00:00:00.000Z', 'cwd': workspace.path})}\n',
      );
      final LaunchPlan plan = SessionLauncher().inspect(
        SessionTarget(
          client: 'pi',
          conversationId: id,
          workspacePath: workspace.path,
        ),
      );
      final Map<String, Object?> resumed = await state(plan.arguments);
      expect(resumed['sessionId'], id);
      expect(resumed['sessionFile'], session.path);
    },
    skip: pi == null
        ? 'Set PI_EXECUTABLE to run an isolated real-Pi RPC check.'
        : false,
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
