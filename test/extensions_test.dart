import 'dart:convert';
import 'dart:io';

import 'package:agent_session_launcher/agent_session_launcher.dart';
import 'package:agent_session_launcher/protocol.dart';
import 'package:test/test.dart';

ExtensionFile ext(String name, Map<String, Object?> client) => ExtensionFile(
  name,
  jsonEncode(<String, Object?>{'schemaVersion': 1, ...client}),
);

LauncherConfig load(
  List<ExtensionFile> extensions, {
  Map<String, Object?> host = const <String, Object?>{},
}) => LauncherConfig.fromJson(<String, Object?>{
  'schemaVersion': 1,
  'clients': host,
}, extensions: extensions);

Map<String, Object?> command(List<String> command, {String? format}) =>
    <String, Object?>{
      'launch': <String, Object?>{'command': command, 'idFormat': ?format},
    };

Map<String, String?> errors(LauncherConfig config) => <String, String?>{
  for (final ExtensionProblem problem in config.extensionErrors)
    problem.file ?? '': problem.message,
};

const String uuid = 'a45cce14-b0be-4aea-a8f9-e88195674770';

void main() {
  test('an extension file adds a client named after the file', () {
    final LauncherConfig config = load(<ExtensionFile>[
      ext('acme-agent.json', <String, Object?>{
        'name': 'Acme Agent',
        'aliases': <String>['Acme Agent CLI'],
        ...command(<String>['/opt/acme/bin/acme-agent', 'resume', '{id}']),
      }),
    ]);
    expect(config.extensionErrors, isEmpty);
    expect(config.classify('Acme Agent CLI'), 'acme-agent');
    expect(config.classify('acme-agent'), 'acme-agent');
    final ClientDefinition client = config.client('acme-agent')!;
    expect(client.origin, 'extension');
    expect(client.extensionFile, 'acme-agent.json');
    expect(client.builtin, isFalse);
    final LaunchPlan plan =
        SessionLauncher(config: config, operatingSystem: 'macos').inspect(
          const SessionTarget(
            client: 'acme-agent',
            conversationId: 'session-1',
            workspacePath: '/workspace',
          ),
        );
    expect(plan.executable, '/opt/acme/bin/acme-agent');
    expect(plan.arguments, <String>['resume', 'session-1']);
  });

  test('a ~/ executable expands to the home directory when planned', () {
    final LauncherConfig config = load(<ExtensionFile>[
      ext('acme-agent.json', command(<String>['~/bin/acme', '{id}'])),
    ]);
    const target = SessionTarget(
      client: 'acme-agent',
      conversationId: 'x',
      workspacePath: '/workspace',
    );
    expect(
      SessionLauncher(
        config: config,
        operatingSystem: 'macos',
        homeDirectory: '/Users/me/',
      ).inspect(target).executable,
      '/Users/me/bin/acme',
    );
    expect(
      SessionLauncher(
            config: config,
            operatingSystem: 'windows',
            homeDirectory: r'C:\Users\me',
          )
          .inspect(
            const SessionTarget(
              client: 'acme-agent',
              conversationId: 'x',
              workspacePath: r'C:\workspace',
            ),
          )
          .executable,
      r'C:\Users\me\bin\acme',
    );
    expect(
      () => SessionLauncher(
        config: config,
        operatingSystem: 'macos',
        homeDirectory: '',
      ).inspect(target),
      throwsA(
        isA<SessionLaunchException>().having(
          (e) => e.code,
          'code',
          'unsupported_platform',
        ),
      ),
    );
  });

  test('an extension may customize a built-in client within its rules', () {
    final LauncherConfig config = load(<ExtensionFile>[
      ext(
        'claude-code.json',
        command(<String>['claude-work', '--resume', '{id}']),
      ),
      ext(
        'pi.json',
        command(<String>['pi', '--session', '{id}'], format: 'safe'),
      ),
      ext('codex.json', <String, Object?>{'name': 'Codex'}),
      ext('codex-app.json', command(<String>['codex', '{id}'])),
    ]);
    final ClientDefinition claude = config.client('claude-code')!;
    expect(claude.launch!.command.first, 'claude-work');
    expect(claude.origin, 'builtin');
    expect(claude.builtin, isTrue);
    expect(claude.extensionFile, 'claude-code.json');
    expect(config.classify('Claude Code CLI'), 'claude-code');
    expect(errors(config), <String, Object?>{
      'pi.json': r'$.launch.idFormat: must stay uuid for this client.',
      'codex.json': contains('cannot be configured'),
      'codex-app.json': contains('already a source label'),
    });
    expect(config.client('pi')!.launch!.idFormat, IdFormat.uuid);
    expect(config.client('pi')!.extensionFile, isNull);
  });

  test('a bad file skips only itself', () {
    final LauncherConfig config = load(<ExtensionFile>[
      const ExtensionFile('broken.json', '{not json'),
      const ExtensionFile('old.json', '{"name":"Old"}'),
      const ExtensionFile('Upper.json', '{"schemaVersion":1}'),
      const ExtensionFile('extra.json', '{"schemaVersion":1,"command":[]}'),
      const ExtensionFile.unreadable(
        'large.json',
        'The file is larger than 16 KiB.',
      ),
      const ExtensionFile.unreadable(
        null,
        'The extensions directory could not be read.',
      ),
      ext('good.json', command(<String>['good', '{id}'])),
    ]);
    expect(errors(config), <String, Object?>{
      'broken.json': r'$: the file is not valid JSON.',
      'old.json': r'$.schemaVersion: must be 1.',
      'Upper.json': contains('the file name must be a client ID'),
      'extra.json': r'$: unsupported field "command".',
      'large.json': 'The file is larger than 16 KiB.',
      '': 'The extensions directory could not be read.',
    });
    expect(config.client('good')!.launch, isNotNull);
    expect(config.client('broken'), isNull);
    expect(config.extensionErrors.last.toJson(), <String, Object?>{
      'message': 'The extensions directory could not be read.',
    });
  });

  test('conflicting source labels skip every file involved', () {
    final LauncherConfig config = load(<ExtensionFile>[
      ext('acme.json', <String, Object?>{
        'aliases': <String>['Acme'],
      }),
      ext('acme-cli.json', <String, Object?>{
        'aliases': <String>['ACME'],
      }),
      ext('fake-pi.json', <String, Object?>{
        'aliases': <String>['Pi'],
      }),
      ext('fine.json', <String, Object?>{}),
    ]);
    expect(errors(config), <String, Object?>{
      'acme.json':
          r'$: "acme" is also claimed by acme-cli.json; both files are skipped.',
      'acme-cli.json':
          r'$: "acme" is also claimed by acme.json; both files are skipped.',
      'fake-pi.json': r'$.aliases: "pi" already identifies "pi".',
    });
    expect(config.classify('Acme'), 'unknown');
    expect(config.classify('Pi'), 'pi');
    expect(config.client('fine'), isNotNull);
  });

  test('host configuration is applied last and never broken by extensions', () {
    final LauncherConfig config = load(
      <ExtensionFile>[
        ext('acme-agent.json', command(<String>['acme', '{id}'])),
        ext('team-tool.json', <String, Object?>{
          'aliases': <String>['Team Tool'],
        }),
        ext(
          'opencode-cli.json',
          command(<String>['opencode', '-s', '{id}'], format: 'uuid'),
        ),
      ],
      host: <String, Object?>{
        'acme-agent': <String, Object?>{
          'enabled': false,
          'preferences': <String, Object?>{'macosTerminal': 'iterm'},
        },
        'team-desktop': <String, Object?>{
          'aliases': <String>['Team Tool'],
          'launch': <String, Object?>{'uri': 'team://open/{id}'},
        },
        'opencode-cli': command(<String>['opencode', '--session', '{id}']),
      },
    );
    final ClientDefinition acme = config.client('acme-agent')!;
    expect(acme.enabled, isFalse);
    expect(acme.origin, 'extension');
    expect(acme.preferences!.macosTerminal, MacosTerminal.iterm);
    expect(acme.launch!.command, <String>['acme', '{id}']);
    expect(errors(config), <String, Object?>{
      'team-tool.json':
          r'$: "team-tool" already identifies "team-desktop" in the host configuration.',
    });
    expect(config.classify('Team Tool'), 'team-desktop');
    expect(config.client('team-desktop')!.origin, 'host');
    final ClientDefinition opencode = config.client('opencode-cli')!;
    expect(opencode.launch!.command, <String>['opencode', '--session', '{id}']);
    expect(opencode.launch!.idFormat, IdFormat.uuid);
    expect(
      () => load(
        <ExtensionFile>[ext('fine.json', <String, Object?>{})],
        host: <String, Object?>{'codex': <String, Object?>{}},
      ),
      throwsA(
        isA<SessionLaunchException>().having(
          (e) => e.code,
          'code',
          'invalid_configuration',
        ),
      ),
    );
  });

  test('host aliases checked against an extension ID stay valid', () {
    final LauncherConfig config = load(
      <ExtensionFile>[ext('acme.json', <String, Object?>{})],
      host: <String, Object?>{
        'acme-desktop': <String, Object?>{
          'aliases': <String>['acme'],
        },
      },
    );
    expect(errors(config).keys, <String>['acme.json']);
    expect(config.classify('acme'), 'acme-desktop');
  });

  group('reading a directory', () {
    late Directory temp;
    setUp(() async {
      temp = await Directory.systemTemp.createTemp('launcher-extensions-');
    });
    tearDown(() => temp.delete(recursive: true));

    test('reads sorted .json files and ignores everything else', () {
      File('${temp.path}/b.json').writeAsStringSync('{"schemaVersion":1}');
      File('${temp.path}/a.json').writeAsStringSync('{"schemaVersion":1}');
      File('${temp.path}/.hidden.json').writeAsStringSync('{}');
      File('${temp.path}/notes.txt').writeAsStringSync('');
      Directory('${temp.path}/nested.json').createSync();
      File('${temp.path}/big.json').writeAsStringSync(' ' * 16385);
      final List<ExtensionFile> files = readExtensionDirectory(temp.path);
      expect(files.map((f) => f.name), <String>[
        'a.json',
        'b.json',
        'big.json',
      ]);
      expect(files.last.error, 'The file is larger than 16 KiB.');
      expect(readExtensionDirectory('${temp.path}/missing'), isEmpty);
    });

    test(
      'refuses files and directories other users can write',
      () async {
        final File file = File('${temp.path}/open.json')
          ..writeAsStringSync('{"schemaVersion":1}');
        await Process.run('chmod', <String>['666', file.path]);
        expect(
          readExtensionDirectory(temp.path).single.error,
          'The file is writable by other users.',
        );
        await Process.run('chmod', <String>['777', temp.path]);
        expect(
          readExtensionDirectory(temp.path).single.error,
          'The extensions directory is writable by other users.',
        );
      },
      skip: Platform.isWindows ? 'POSIX permissions only.' : false,
    );

    test('the shipped examples load cleanly', () {
      final LauncherConfig config = LauncherConfig.load(
        extensionsDirectory: 'example/extensions',
      );
      expect(config.extensionErrors, isEmpty);
      expect(config.client('acme-agent')!.name, 'Acme Agent');
      expect(config.client('acme-desktop')!.launch!.kind, 'uri');
    });
  });

  test('the default directory follows each platform convention', () {
    expect(
      defaultExtensionsDirectory(
        environment: <String, String>{'HOME': '/Users/me'},
        operatingSystem: 'macos',
      ),
      '/Users/me/.config/agent-session-launcher/clients',
    );
    expect(
      defaultExtensionsDirectory(
        environment: <String, String>{
          'HOME': '/home/me',
          'XDG_CONFIG_HOME': '/cfg',
        },
        operatingSystem: 'linux',
      ),
      '/cfg/agent-session-launcher/clients',
    );
    expect(
      defaultExtensionsDirectory(
        environment: <String, String>{
          'HOME': '/home/me',
          'XDG_CONFIG_HOME': 'relative',
        },
        operatingSystem: 'linux',
      ),
      '/home/me/.config/agent-session-launcher/clients',
    );
    expect(
      defaultExtensionsDirectory(
        environment: <String, String>{
          'APPDATA': r'C:\Users\me\AppData\Roaming',
        },
        operatingSystem: 'windows',
      ),
      r'C:\Users\me\AppData\Roaming\agent-session-launcher\clients',
    );
    expect(
      defaultExtensionsDirectory(
        environment: const <String, String>{},
        operatingSystem: 'linux',
      ),
      isNull,
    );
  });

  test('protocol clients reports origin and skipped files', () async {
    final Map<String, Object?> response = await handleRequestFor(
      load(<ExtensionFile>[
        ext('acme-agent.json', command(<String>['acme', '{id}'])),
        const ExtensionFile('bad.json', '[]'),
      ]),
    );
    final List<Object?> clients = response['clients']! as List<Object?>;
    final Map<String, Object?> acme = clients
        .cast<Map<String, Object?>>()
        .firstWhere((c) => c['id'] == 'acme-agent');
    expect(acme['origin'], 'extension');
    expect(acme['extensionFile'], 'acme-agent.json');
    expect(response['extensionErrors'], <Object?>[
      <String, Object?>{
        'file': 'bad.json',
        'message': r'$: must be an object.',
      },
    ]);
  });
}

Future<Map<String, Object?>> handleRequestFor(LauncherConfig config) =>
    handleRequest(<String, Object?>{
      'version': 1,
      'action': 'clients',
    }, launcher: SessionLauncher(config: config));
