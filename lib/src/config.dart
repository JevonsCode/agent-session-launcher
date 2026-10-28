import 'dart:convert';

import 'catalog.dart';
import 'identity.dart';
import 'models.dart';

/// Session ID shapes. Every format is a subset of [safe].
enum IdFormat {
  safe('safe'),
  uuid('uuid'),
  claudeDesktop('claude-desktop'),
  cursorBackground('cursor-background');

  const IdFormat(this.value);
  final String value;

  /// Returns the trimmed ID or throws a target error.
  String check(String? raw) {
    final String id = (raw ?? '').trim();
    if (id.isEmpty || id.length > 256 || !_safeId.hasMatch(id)) {
      throw const SessionLaunchException(
        'invalid_target',
        'A valid session ID is required.',
      );
    }
    switch (this) {
      case IdFormat.safe:
        break;
      case IdFormat.uuid:
        if (!_uuid.hasMatch(id)) {
          throw const SessionLaunchException(
            'invalid_target',
            'This client requires a full UUID session ID.',
          );
        }
      case IdFormat.claudeDesktop:
        if (!_claudeDesktopId.hasMatch(id)) {
          throw const SessionLaunchException(
            'invalid_target',
            'A valid Claude Desktop host session ID is required.',
          );
        }
      case IdFormat.cursorBackground:
        if (!id.startsWith('bc-')) {
          throw const SessionLaunchException(
            'unsupported_target',
            'Only Cursor background-agent links are supported.',
          );
        }
    }
    return id;
  }
}

/// A validated launch definition. Only the `{id}` token is ever substituted.
final class LaunchSpec {
  const LaunchSpec._({
    required this.kind,
    required this.idSource,
    required this.idFormat,
    this.command = const <String>[],
    this.scheme,
    this.host,
    this.pathSegments = const <String>[],
    this.query = const <String, String>{},
  });

  /// `cli` or `uri`.
  final String kind;

  /// `conversationId` or `hostSessionId`.
  final String idSource;
  final IdFormat idFormat;

  /// Executable followed by fixed arguments, for `cli`.
  final List<String> command;
  final String? scheme;
  final String? host;
  final List<String> pathSegments;
  final Map<String, String> query;

  LaunchPlan plan(String id, {String? workspacePath}) {
    String fill(String token) => token == '{id}' ? id : token;
    if (kind == 'cli') {
      return LaunchPlan(
        kind: 'cli',
        executable: command.first,
        arguments: List<String>.unmodifiable(command.skip(1).map(fill)),
        workspacePath: workspacePath,
      );
    }
    return LaunchPlan(
      kind: 'uri',
      uri: Uri(
        scheme: scheme,
        host: host,
        pathSegments: pathSegments.map(fill),
        queryParameters: query.isEmpty
            ? null
            : query.map((key, value) => MapEntry(key, fill(value))),
      ),
    );
  }
}

/// One client after merging the built-in catalog with host configuration.
final class ClientDefinition {
  const ClientDefinition({
    required this.id,
    required this.name,
    required this.aliases,
    required this.enabled,
    required this.builtin,
    this.ambiguous = false,
    this.launch,
    this.preferences,
  });

  final String id;
  final String name;

  /// Normalized source labels that classify as this client.
  final List<String> aliases;
  final bool enabled;
  final bool builtin;

  /// The label is known to cover several surfaces; never openable.
  final bool ambiguous;

  /// Null when no verified opening method exists.
  final LaunchSpec? launch;
  final LaunchPreferences? preferences;
}

/// Host-owned launcher configuration, validated as a whole before use.
///
/// The document has the same shape as the built-in catalog. Entries in
/// `clients` are merged by ID: listed fields replace the built-in value,
/// `aliases` are added, and unlisted clients keep their defaults. Session
/// requests can never supply configuration.
final class LauncherConfig {
  LauncherConfig._(this.preferences, this._clients, this._aliases);

  /// Built-in clients only.
  static final LauncherConfig defaults = LauncherConfig.fromJson(
    const <String, Object?>{'schemaVersion': 1},
  );

  /// Parses JSON text, e.g. the contents of a trusted local file.
  factory LauncherConfig.decode(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw const SessionLaunchException(
        'invalid_configuration',
        r'$: the configuration is not valid JSON.',
      );
    }
    return LauncherConfig.fromJson(json);
  }

  factory LauncherConfig.fromJson(Object? json) {
    final Map<String, Object?> root = _object(json, r'$');
    // `$schema` is an editor hint and is ignored.
    _keys(root, const {
      r'$schema',
      'schemaVersion',
      'preferences',
      'clients',
    }, r'$');
    if (root['schemaVersion'] != 1) {
      _fail(r'$.schemaVersion', 'must be 1.');
    }
    final LaunchPreferences preferences = root.containsKey('preferences')
        ? LaunchPreferences.fromJson(
            root['preferences'],
            path: r'$.preferences',
            code: 'invalid_configuration',
          )
        : const LaunchPreferences();
    final builder = _Builder();
    for (final MapEntry<String, Object?> entry in builtinClients.entries) {
      builder.add(entry.key, entry.value, 'builtin.${entry.key}', null);
    }
    if (root.containsKey('clients')) {
      final Map<String, Object?> clients = _object(
        root['clients'],
        r'$.clients',
      );
      if (clients.length > 128) _fail(r'$.clients', 'has too many entries.');
      for (final MapEntry<String, Object?> entry in clients.entries) {
        final String id = entry.key;
        final String path = '\$.clients.$id';
        if (!_clientId.hasMatch(id)) {
          _fail(
            r'$.clients',
            'client IDs use lowercase letters, digits and hyphens '
                '(at most 64 characters).',
          );
        }
        final ClientDefinition? base = builder.clients[id];
        if (base != null && base.ambiguous) {
          _fail(
            path,
            'this label covers several surfaces and cannot be configured; '
            'configure a specific client instead.',
          );
        }
        if (base == null && builder.aliases.containsKey(id)) {
          _fail(path, 'the ID is already a source label of another client.');
        }
        builder.add(id, entry.value, path, base);
      }
    }
    return LauncherConfig._(
      preferences,
      Map<String, ClientDefinition>.unmodifiable(builder.clients),
      Map<String, String>.unmodifiable(builder.aliases),
    );
  }

  /// Host-wide defaults, below per-client and per-request preferences.
  final LaunchPreferences preferences;
  final Map<String, ClientDefinition> _clients;
  final Map<String, String> _aliases;

  /// Every known identity, built-ins first, including ambiguous ones.
  Iterable<ClientDefinition> get clients => _clients.values;

  ClientDefinition? client(String id) => _clients[id];

  /// Maps an explicit source label to a client ID without guessing.
  /// Only the non-secret Claude entrypoint signal may refine a Claude source.
  String classify(String source, {String? claudeEntrypoint}) {
    final String normalized = normalizeAgentSource(source);
    if ((normalized.isEmpty ||
            normalized == 'claude' ||
            normalized == 'claude-code') &&
        claudeEntrypoint?.trim().toLowerCase() == 'claude-desktop') {
      return 'claude-desktop';
    }
    return _aliases[normalized] ?? 'unknown';
  }
}

final class _Builder {
  final Map<String, ClientDefinition> clients = <String, ClientDefinition>{};
  final Map<String, String> aliases = <String, String>{};

  void add(String id, Object? raw, String path, ClientDefinition? base) {
    final bool catalog = path.startsWith('builtin.');
    final Map<String, Object?> json = _object(raw, path);
    _keys(json, {
      'name',
      'enabled',
      'aliases',
      'launch',
      'preferences',
      if (catalog) 'ambiguous',
    }, path);
    String? name;
    if (json.containsKey('name')) {
      name = _text(json['name'], '$path.name', maxLength: 64);
    }
    final Object? enabled = json['enabled'];
    if (json.containsKey('enabled') && enabled is! bool) {
      _fail('$path.enabled', 'must be true or false.');
    }
    final List<String> added = <String>[];
    if (json.containsKey('aliases')) {
      final Object? list = json['aliases'];
      if (list is! List || list.length > 32) {
        _fail('$path.aliases', 'must be a list of at most 32 labels.');
      }
      for (final Object? label in list) {
        final String alias = normalizeAgentSource(
          _text(label, '$path.aliases', maxLength: 128),
        );
        if (alias.isEmpty || alias == 'claude' || alias == 'unknown') {
          _fail('$path.aliases', 'contains a reserved or empty label.');
        }
        added.add(alias);
      }
    }
    if (base == null && !catalog) added.add(id);
    for (final String alias in added) {
      final String? owner = aliases[alias];
      if (owner != null && owner != id) {
        _fail('$path.aliases', '"$alias" already identifies "$owner".');
      }
    }
    for (final String alias in added) {
      aliases[alias] = id;
    }
    clients[id] = ClientDefinition(
      id: id,
      name: name ?? base?.name ?? id,
      aliases: List<String>.unmodifiable(<String>{...?base?.aliases, ...added}),
      enabled: enabled as bool? ?? base?.enabled ?? true,
      builtin: base?.builtin ?? catalog,
      ambiguous: json['ambiguous'] == true,
      launch: json.containsKey('launch')
          ? _launch(json['launch'], '$path.launch', base?.launch)
          : base?.launch,
      preferences: json.containsKey('preferences')
          ? LaunchPreferences.fromJson(
              json['preferences'],
              path: '$path.preferences',
              code: 'invalid_configuration',
            )
          : base?.preferences,
    );
  }
}

LaunchSpec _launch(Object? raw, String path, LaunchSpec? base) {
  final Map<String, Object?> json = _object(raw, path);
  _keys(json, const {'command', 'uri', 'idFormat', 'idSource'}, path);
  if (json.containsKey('command') == json.containsKey('uri')) {
    _fail(path, 'specify exactly one of "command" or "uri".');
  }
  final String kind = json.containsKey('command') ? 'cli' : 'uri';
  IdFormat format = base?.idFormat ?? IdFormat.safe;
  if (json.containsKey('idFormat')) {
    final Object? value = json['idFormat'];
    format =
        IdFormat.values.where((f) => f.value == value).firstOrNull ??
        _fail(
          '$path.idFormat',
          'must be one of ${IdFormat.values.map((f) => f.value).join(', ')}.',
        );
  }
  String source = base?.idSource ?? 'conversationId';
  if (json.containsKey('idSource')) {
    if (kind == 'cli') {
      _fail('$path.idSource', 'applies only to "uri" launches.');
    }
    final Object? value = json['idSource'];
    if (value != 'conversationId' && value != 'hostSessionId') {
      _fail('$path.idSource', 'must be conversationId or hostSessionId.');
    }
    source = value! as String;
  }
  if (base != null) {
    if (base.kind != kind) {
      _fail(path, 'a built-in ${base.kind} client must keep the same kind.');
    }
    if (base.idSource != source) {
      _fail('$path.idSource', 'must stay ${base.idSource} for this client.');
    }
    if (base.idFormat != format && base.idFormat != IdFormat.safe) {
      _fail(
        '$path.idFormat',
        'must stay ${base.idFormat.value} for this client.',
      );
    }
  }
  if (kind == 'cli') {
    if (format != IdFormat.safe && format != IdFormat.uuid) {
      _fail('$path.idFormat', 'command launches use safe or uuid.');
    }
    final Object? list = json['command'];
    if (list is! List || list.length < 2 || list.length > 33) {
      _fail('$path.command', 'must be [executable, ...arguments].');
    }
    final List<String> command = <String>[
      for (final Object? token in list) _text(token, '$path.command'),
    ];
    if (!_executable.hasMatch(command.first)) {
      _fail(
        '$path.command',
        'the executable must be a program name, not a path or shell text.',
      );
    }
    final List<String> arguments = command.sublist(1);
    if (arguments.where((t) => t == '{id}').length != 1) {
      _fail('$path.command', 'arguments must contain "{id}" exactly once.');
    }
    if (arguments.any((t) => t != '{id}' && !_argToken.hasMatch(t))) {
      _fail('$path.command', 'arguments may not contain shell syntax.');
    }
    return LaunchSpec._(
      kind: 'cli',
      idSource: 'conversationId',
      idFormat: format,
      command: List<String>.unmodifiable(command),
    );
  }
  final String template = _text(json['uri'], '$path.uri', maxLength: 1024);
  final RegExpMatch? match = _uriTemplate.firstMatch(template);
  if (match == null) {
    _fail('$path.uri', 'must look like scheme://host/path?key={id}.');
  }
  final String scheme = match.group(1)!;
  if (_blockedSchemes.contains(scheme)) {
    _fail('$path.uri', 'web, file and script schemes are not allowed.');
  }
  final List<String> segments = match
      .group(3)!
      .split('/')
      .where((s) => s.isNotEmpty)
      .toList();
  final Map<String, String> query = <String, String>{};
  final String rawQuery = match.group(4) ?? '';
  for (final String pair
      in rawQuery.isEmpty ? <String>[] : rawQuery.split('&')) {
    final int equals = pair.indexOf('=');
    final String key = equals < 0 ? pair : pair.substring(0, equals);
    final String value = equals < 0 ? '' : pair.substring(equals + 1);
    if (!_uriToken.hasMatch(key) || query.containsKey(key)) {
      _fail('$path.uri', 'query keys must be unique plain tokens.');
    }
    query[key] = value;
  }
  final List<String> tokens = <String>[...segments, ...query.values];
  if (tokens.any((t) => t != '{id}' && !_uriToken.hasMatch(t)) ||
      query.length > 16 ||
      segments.length > 32) {
    _fail('$path.uri', 'path and query values must be plain tokens.');
  }
  if (tokens.where((t) => t == '{id}').length != 1) {
    _fail(
      '$path.uri',
      'must contain "{id}" exactly once, as a whole path segment or query value.',
    );
  }
  return LaunchSpec._(
    kind: 'uri',
    idSource: source,
    idFormat: format,
    scheme: scheme,
    host: match.group(2),
    pathSegments: List<String>.unmodifiable(segments),
    query: Map<String, String>.unmodifiable(query),
  );
}

final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
final RegExp _safeId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]*$');
final RegExp _claudeDesktopId = RegExp(r'^local_[A-Za-z0-9-]{1,64}$');
final RegExp _clientId = RegExp(r'^[a-z][a-z0-9-]{0,63}$');
final RegExp _executable = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');
final RegExp _argToken = RegExp(r'^[A-Za-z0-9._:/+=,-]{1,256}$');
final RegExp _uriToken = RegExp(r'^[A-Za-z0-9._~-]{1,256}$');
final RegExp _uriTemplate = RegExp(
  r'^([a-z][a-z0-9+.-]{0,31})://([a-z0-9][a-z0-9.-]{0,127})((?:/[^/?#]*)*)(?:\?([^#]*))?$',
);
const Set<String> _blockedSchemes = <String>{
  'http',
  'https',
  'file',
  'data',
  'javascript',
  'mailto',
};

Map<String, Object?> _object(Object? value, String path) {
  if (value is! Map<String, Object?>) _fail(path, 'must be an object.');
  return value;
}

String _text(Object? value, String path, {int maxLength = 256}) {
  if (value is! String || value.isEmpty || value.length > maxLength) {
    _fail(path, 'must be non-empty text of at most $maxLength characters.');
  }
  return value;
}

void _keys(Map<String, Object?> value, Set<String> allowed, String path) {
  for (final String key in value.keys) {
    if (!allowed.contains(key)) _fail(path, 'unsupported field "$key".');
  }
}

Never _fail(String path, String reason) =>
    throw SessionLaunchException('invalid_configuration', '$path: $reason');
