import 'agent_session_launcher.dart';

/// The caller is responsible for authorizing an explicit `open` request.
Future<Map<String, Object?>> handleRequest(
  Object? input, {
  SessionLauncher? launcher,
}) async {
  try {
    final SessionLauncher service = launcher ?? SessionLauncher();
    if (input is! Map<String, Object?> ||
        input['version'] != 1 ||
        input['action'] is! String) {
      throw const SessionLaunchException(
        'invalid_request',
        'Expected a version 1 request object.',
      );
    }
    final String action = input['action']! as String;
    if (action == 'classify') {
      _onlyKeys(input, const <String>{
        'version',
        'action',
        'source',
        'claudeEntrypoint',
      });
      final String source = _string(input, 'source', required: true)!;
      final String? entrypoint = _string(input, 'claudeEntrypoint');
      return <String, Object?>{
        'version': 1,
        'ok': true,
        'client': service.classify(source, claudeEntrypoint: entrypoint),
      };
    }
    if (action == 'clients') {
      _onlyKeys(input, const <String>{'version', 'action'});
      return <String, Object?>{
        'version': 1,
        'ok': true,
        'clients': <Object?>[
          for (final ClientInfo client in service.clients()) client.toJson(),
        ],
        'extensionErrors': <Object?>[
          for (final ExtensionProblem problem in service.config.extensionErrors)
            problem.toJson(),
        ],
      };
    }
    if (action != 'inspect' && action != 'open') {
      throw const SessionLaunchException(
        'invalid_request',
        'Unsupported action.',
      );
    }
    _onlyKeys(input, const <String>{
      'version',
      'action',
      'target',
      'preferences',
    });
    final Object? rawTarget = input['target'];
    if (rawTarget is! Map<String, Object?>) {
      throw const SessionLaunchException(
        'invalid_request',
        'Target must be an object.',
      );
    }
    _onlyKeys(rawTarget, const <String>{
      'client',
      'conversationId',
      'workspacePath',
      'hostSessionId',
    });
    final target = SessionTarget(
      client: _string(rawTarget, 'client', required: true)!,
      conversationId: _string(rawTarget, 'conversationId'),
      workspacePath: _string(rawTarget, 'workspacePath'),
      hostSessionId: _string(rawTarget, 'hostSessionId'),
    );
    LaunchPreferences? preferences;
    if (input.containsKey('preferences')) {
      final Object? raw = input['preferences'];
      if (raw is! Map<String, Object?>) {
        throw const SessionLaunchException(
          'invalid_request',
          'Preferences must be an object.',
        );
      }
      _onlyKeys(raw, const <String>{'macosTerminal', 'itermOpenMode'});
      preferences = LaunchPreferences.fromJson(raw);
    }
    if (action == 'inspect') {
      final LaunchPlan plan = service.inspect(target);
      return <String, Object?>{
        'version': 1,
        'ok': true,
        'plan': plan.toJson(),
        'openSupported': service.supportsOpening(plan),
      };
    }
    await service.open(target, preferences: preferences);
    return <String, Object?>{
      'version': 1,
      'ok': true,
      'status': 'launch_requested',
    };
  } on SessionLaunchException catch (error) {
    return <String, Object?>{
      'version': 1,
      'ok': false,
      'error': <String, Object?>{'code': error.code, 'message': error.message},
    };
  } on Object {
    return <String, Object?>{
      'version': 1,
      'ok': false,
      'error': <String, Object?>{
        'code': 'internal_error',
        'message': 'The request could not be processed.',
      },
    };
  }
}

void _onlyKeys(Map<String, Object?> object, Set<String> allowed) {
  if (object.keys.any((String key) => !allowed.contains(key))) {
    throw const SessionLaunchException(
      'invalid_request',
      'The request contains unsupported fields.',
    );
  }
}

String? _string(
  Map<String, Object?> object,
  String key, {
  bool required = false,
}) {
  final Object? value = object[key];
  if (!object.containsKey(key) && !required) return null;
  if (value is! String || (required && value.trim().isEmpty)) {
    throw const SessionLaunchException(
      'invalid_request',
      'A required text field is invalid.',
    );
  }
  return value;
}
