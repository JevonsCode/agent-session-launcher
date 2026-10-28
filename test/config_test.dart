import 'dart:io';

import 'package:agent_session_launcher/agent_session_launcher.dart';
import 'package:test/test.dart';

LauncherConfig config(
  Map<String, Object?> clients, {
  Map<String, Object?>? preferences,
}) => LauncherConfig.fromJson(<String, Object?>{
  'schemaVersion': 1,
  'preferences': ?preferences,
  'clients': clients,
});

Map<String, Object?> cli(List<String> command, {String? format}) =>
    <String, Object?>{
      'launch': <String, Object?>{'command': command, 'idFormat': ?format},
    };

Matcher invalidConfig([Object? message]) => throwsA(
  isA<SessionLaunchException>()
      .having((e) => e.code, 'code', 'invalid_configuration')
      .having((e) => e.message, 'message', message ?? anything),
);

Matcher failsWith(String code) =>
    throwsA(isA<SessionLaunchException>().having((e) => e.code, 'code', code));

const String uuid = 'a45cce14-b0be-4aea-a8f9-e88195674770';

void main() {
  test('a single override retains built-ins and their source aliases', () {
    final launcher = SessionLauncher(
      operatingSystem: 'macos',
      config: config(<String, Object?>{
        'claude-code': cli(<String>['claude', '--session', '{id}']),
      }),
    );
    final plan = launcher.inspect(
      const SessionTarget(
        client: 'claude-code',
        conversationId: 'session-1',
        workspacePath: '/workspace',
      ),
    );
    expect(plan.arguments, <String>['--session', 'session-1']);
    expect(launcher.classify('Claude Code CLI'), 'claude-code');
    expect(
      launcher
          .inspect(
            const SessionTarget(
              client: 'pi',
              conversationId: uuid,
              workspacePath: '/workspace',
            ),
          )
          .arguments,
      <String>['--session', uuid],
    );
  });

  test('a custom client is classified by its ID, name labels and aliases', () {
    final launcher = SessionLauncher(
      operatingSystem: 'macos',
      config: config(<String, Object?>{
        'example-desktop': <String, Object?>{
          'name': 'Example Desktop',
          'aliases': <String>['Example App'],
          'launch': <String, Object?>{
            'uri': 'example://session/open?id={id}',
            'idSource': 'hostSessionId',
          },
        },
      }),
    );
    expect(launcher.classify('Example App'), 'example-desktop');
    expect(launcher.classify('example-desktop'), 'example-desktop');
    final plan = launcher.inspect(
      const SessionTarget(
        client: 'example-desktop',
        hostSessionId: 'session:42',
      ),
    );
    expect(plan.uri.toString(), 'example://session/open?id=session%3A42');
  });

  test('custom CLI clients plan on Windows while Linux reports no opener', () {
    final rules = config(<String, Object?>{
      'example-cli': cli(<String>['example', '--resume', '{id}']),
    });
    final windows = SessionLauncher(operatingSystem: 'windows', config: rules);
    final windowsPlan = windows.inspect(
      const SessionTarget(
        client: 'example-cli',
        conversationId: 'abc-123',
        workspacePath: r'C:\project',
      ),
    );
    expect(windowsPlan.arguments, <String>['--resume', 'abc-123']);
    expect(windows.supportsOpening(windowsPlan), isTrue);
    final linux = SessionLauncher(operatingSystem: 'linux', config: rules);
    final linuxPlan = linux.inspect(
      const SessionTarget(
        client: 'example-cli',
        conversationId: 'abc-123',
        workspacePath: '/project',
      ),
    );
    expect(linux.supportsOpening(linuxPlan), isFalse);
  });

  test('a Desktop URI override keeps the host-specific identity', () {
    final launcher = SessionLauncher(
      operatingSystem: 'macos',
      config: config(<String, Object?>{
        'claude-desktop': <String, Object?>{
          'launch': <String, Object?>{
            'uri': 'claude://code/resume?session={id}',
          },
        },
      }),
    );
    expect(
      launcher
          .inspect(
            const SessionTarget(
              client: 'claude-desktop',
              conversationId: 'other-cli-session',
              hostSessionId: 'local_correct',
            ),
          )
          .uri
          .toString(),
      'claude://code/resume?session=local_correct',
    );
    expect(
      () => launcher.inspect(
        const SessionTarget(client: 'claude-desktop', hostSessionId: 'wrong'),
      ),
      failsWith('invalid_target'),
    );
  });

  test('a specific surface without a built-in opener can be configured', () {
    final launcher = SessionLauncher(
      operatingSystem: 'macos',
      config: config(<String, Object?>{
        'windsurf': <String, Object?>{
          'launch': <String, Object?>{'uri': 'windsurf://chat/{id}'},
        },
      }),
    );
    expect(
      launcher
          .inspect(
            const SessionTarget(client: 'windsurf', conversationId: 'c-1'),
          )
          .uri
          .toString(),
      'windsurf://chat/c-1',
    );
  });

  test('disabled clients still classify but cannot be inspected', () {
    final launcher = SessionLauncher(
      operatingSystem: 'macos',
      config: config(<String, Object?>{
        'cursor': <String, Object?>{'enabled': false},
      }),
    );
    expect(launcher.classify('Cursor'), 'cursor');
    expect(
      () => launcher.inspect(
        const SessionTarget(client: 'cursor', conversationId: 'bc-1'),
      ),
      failsWith('client_disabled'),
    );
    final ClientInfo cursor = launcher.clients().singleWhere(
      (c) => c.id == 'cursor',
    );
    expect(cursor.enabled, isFalse);
    expect(cursor.kind, 'uri');
  });

  test('clients() lists specific clients for a settings screen', () {
    final List<ClientInfo> clients = SessionLauncher(
      operatingSystem: 'linux',
    ).clients();
    final Map<String, ClientInfo> byId = <String, ClientInfo>{
      for (final ClientInfo c in clients) c.id: c,
    };
    expect(byId.keys, isNot(contains('codex')));
    expect(byId.keys, isNot(contains('claude-code-unknown')));
    expect(byId.keys, isNot(contains('unknown')));
    expect(byId['codex-desktop']!.toJson(), <String, Object?>{
      'id': 'codex-desktop',
      'name': 'Codex Desktop',
      'enabled': true,
      'builtin': true,
      'kind': 'uri',
      'idSource': 'conversationId',
      'idFormat': 'uuid',
      'requiresWorkspace': false,
      'openSupported': true,
    });
    expect(byId['pi']!.requiresWorkspace, isTrue);
    expect(byId['pi']!.openSupported, isFalse);
    expect(byId['windsurf']!.kind, isNull);
    expect(byId['windsurf']!.openSupported, isFalse);
  });

  test(
    'preferences resolve request, then client, then host defaults',
    () async {
      final temp = await Directory.systemTemp.createTemp('launcher-prefs-');
      addTearDown(() => temp.delete(recursive: true));
      final List<String> scripts = <String>[];
      final launcher = SessionLauncher(
        operatingSystem: 'macos',
        processRunner: (command, args, {workingDirectory}) async {
          scripts.add(args.last);
          return ProcessResult(1, 0, '', '');
        },
        config: config(
          <String, Object?>{
            'pi': <String, Object?>{
              'preferences': <String, Object?>{'macosTerminal': 'terminal'},
            },
          },
          preferences: <String, Object?>{
            'macosTerminal': 'iterm',
            'itermOpenMode': 'new-tab',
          },
        ),
      );
      SessionTarget target(String client) => SessionTarget(
        client: client,
        conversationId: uuid,
        workspacePath: temp.path,
      );
      await launcher.open(target('claude-code'));
      await launcher.open(target('pi'));
      await launcher.open(
        target('pi'),
        preferences: const LaunchPreferences(
          macosTerminal: MacosTerminal.iterm,
        ),
      );
      expect(scripts[0], contains('create tab with default profile'));
      expect(scripts[1], contains('tell application "Terminal"'));
      expect(scripts[2], contains('tell application "iTerm"'));
      expect(scripts[2], contains('create tab with default profile'));
    },
    skip: Platform.isWindows
        ? 'A simulated macOS workspace needs a POSIX temporary path.'
        : false,
  );

  test('ambiguous or colliding labels cannot be redirected to a client', () {
    expect(
      () => config(<String, Object?>{
        'example-cli': <String, Object?>{
          ...cli(<String>['example', '--resume', '{id}']),
          'aliases': <String>['Claude Code'],
        },
      }),
      invalidConfig(contains('already identifies "claude-code-unknown"')),
    );
    expect(
      () => config(<String, Object?>{
        'opencode': cli(<String>['opencode', '--session', '{id}']),
      }),
      invalidConfig(contains('covers several surfaces')),
    );
    expect(
      () => config(<String, Object?>{
        'claude-code-cli': cli(<String>['claude', '--resume', '{id}']),
      }),
      invalidConfig(contains('source label of another client')),
    );
    expect(
      () => config(<String, Object?>{
        'example-cli': <String, Object?>{
          ...cli(<String>['example', '--resume', '{id}']),
          'aliases': <String>['Shared'],
        },
        'other-cli': <String, Object?>{
          ...cli(<String>['other', '--resume', '{id}']),
          'aliases': <String>['Shared'],
        },
      }),
      invalidConfig(),
    );
    expect(
      () => config(<String, Object?>{
        'example-cli': <String, Object?>{'ambiguous': true},
      }),
      invalidConfig(contains('unsupported field "ambiguous"')),
    );
  });

  test('configuration cannot weaken built-in session identity rules', () {
    expect(
      () => config(<String, Object?>{
        'pi': cli(<String>['pi', '--session', '{id}'], format: 'safe'),
      }),
      invalidConfig(
        r'$.clients.pi.launch.idFormat: must stay uuid for this client.',
      ),
    );
    expect(
      () => config(<String, Object?>{
        'codex-desktop': cli(<String>['codex', 'resume', '{id}']),
      }),
      invalidConfig(contains('must keep the same kind')),
    );
    expect(
      () => config(<String, Object?>{
        'claude-desktop': <String, Object?>{
          'launch': <String, Object?>{
            'uri': 'claude://code/continue?session={id}',
            'idSource': 'conversationId',
          },
        },
      }),
      invalidConfig(contains('must stay hostSessionId')),
    );
    expect(
      config(<String, Object?>{
        'opencode-cli': cli(<String>[
          'opencode',
          '--session',
          '{id}',
        ], format: 'uuid'),
      }).client('opencode-cli')!.launch!.idFormat,
      IdFormat.uuid,
    );
  });

  test('malformed definitions cannot introduce commands or arbitrary URLs', () {
    for (final (Map<String, Object?> launch, String hint)
        in <(Map<String, Object?>, String)>[
          (
            <String, Object?>{
              'command': <String>['/bin/sh', '--resume', '{id}'],
            },
            'program name',
          ),
          (
            <String, Object?>{
              'command': <String>['example', '{id}', '{id}'],
            },
            'exactly once',
          ),
          (
            <String, Object?>{
              'command': <String>['example', '--resume;touch', '{id}'],
            },
            'shell syntax',
          ),
          (
            <String, Object?>{
              'command': <String>['example', '--id={id}'],
            },
            'exactly once',
          ),
          (<String, Object?>{'uri': 'https://example.com/{id}'}, 'schemes'),
          (<String, Object?>{'uri': 'example://open/x{id}'}, 'plain tokens'),
          (<String, Object?>{'uri': 'example://open/{id}#frag'}, 'scheme://'),
          (
            <String, Object?>{
              'command': <String>['example', '{id}'],
              'uri': 'example://open/{id}',
            },
            'exactly one',
          ),
        ]) {
      expect(
        () => config(<String, Object?>{
          'example-cli': <String, Object?>{'launch': launch},
        }),
        invalidConfig(
          allOf(startsWith(r'$.clients.example-cli.launch'), contains(hint)),
        ),
        reason: '$launch',
      );
    }
  });

  test('the shipped example configuration is valid', () {
    final LauncherConfig example = LauncherConfig.decode(
      File('example/config/launcher.json').readAsStringSync(),
    );
    expect(example.preferences.macosTerminal, MacosTerminal.iterm);
    expect(example.client('windsurf')!.enabled, isFalse);
    expect(example.classify('OpenCode Terminal'), 'opencode-cli');
  });

  test('document-level errors name the failing location', () {
    expect(
      () => LauncherConfig.decode('{bad json'),
      invalidConfig(contains('not valid JSON')),
    );
    expect(
      () => LauncherConfig.fromJson(<String, Object?>{'schemaVersion': 2}),
      invalidConfig(r'$.schemaVersion: must be 1.'),
    );
    expect(
      () => config(
        <String, Object?>{},
        preferences: <String, Object?>{'macosTerminal': 'warp'},
      ),
      invalidConfig(startsWith(r'$.preferences: macosTerminal')),
    );
    expect(
      () => config(<String, Object?>{'Bad ID': <String, Object?>{}}),
      invalidConfig(startsWith(r'$.clients:')),
    );
  });
}
