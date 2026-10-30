import 'dart:convert';

import 'catalog.dart';
import 'extensions.dart';
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

/// One client after merging the built-in catalog, user extensions and host
/// configuration.
final class ClientDefinition {
  const ClientDefinition({
    required this.id,
    required this.name,
    required this.aliases,
    required this.enabled,
    required this.builtin,
    this.origin = 'builtin',
    this.extensionFile,
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

  /// Where the client was first defined: `builtin`, `extension` or `host`.
  final String origin;

  /// The user extension file that defines or customizes this client.
  final String? extensionFile;

  /// The label is known to cover several surfaces; never openable.
  final bool ambiguous;

  /// Null when no verified opening method exists.
  final LaunchSpec? launch;
  final LaunchPreferences? preferences;
}

/// Launcher configuration, validated before use.
///
/// Layers merge by client ID in this order: the built-in catalog, user
/// extension files, then the host configuration. Each layer uses the shape of
/// the built-in catalog: listed fields replace earlier values, `aliases` are
/// added, and unlisted clients keep their definitions. A bad host
/// configuration fails as a whole; a bad extension file only skips that file
/// and is reported in [extensionErrors]. Session requests never supply
/// configuration.
final class LauncherConfig {
  LauncherConfig._(
    this.preferences,
    this._clients,
    this._aliases,
    this.extensionErrors,
  );

  /// Built-in clients only.
  static final LauncherConfig defaults = LauncherConfig.fromJson(
    const <String, Object?>{'schemaVersion': 1},
  );

  /// Parses JSON text, e.g. the contents of a trusted local file.
  factory LauncherConfig.decode(
    String text, {
    List<ExtensionFile> extensions = const <ExtensionFile>[],
  }) => LauncherConfig.fromJson(
    _decode(text, r'$', 'the configuration is not valid JSON.'),
    extensions: extensions,
  );

  /// Combines optional host configuration text with the extension files in
  /// [extensionsDirectory], typically [defaultExtensionsDirectory].
  factory LauncherConfig.load({
    String? hostConfig,
    String? extensionsDirectory,
  }) => LauncherConfig.fromJson(
    hostConfig == null
        ? const <String, Object?>{'schemaVersion': 1}
        : _decode(hostConfig, r'$', 'the configuration is not valid JSON.'),
    extensions: extensionsDirectory == null
        ? const <ExtensionFile>[]
        : readExtensionDirectory(extensionsDirectory),
  );

  factory LauncherConfig.fromJson(
    Object? json, {
    List<ExtensionFile> extensions = const <ExtensionFile>[],
  }) {
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
    final Map<String, Object?> hostClients = root.containsKey('clients')
        ? _object(root['clients'], r'$.clients')
        : const <String, Object?>{};
    if (hostClients.length > 128) {
      _fail(r'$.clients', 'has too many entries.');
    }
    if (!hostClients.keys.every(_clientId.hasMatch)) {
      _fail(
        r'$.clients',
        'client IDs use lowercase letters, digits and hyphens '
            '(at most 64 characters).',
      );
    }

    // The host configuration is validated on its own first, so an extension
    // can never make it fail; source labels it claims win over extensions.
    final _Builder builtins = _Builder.builtins();
    final _Builder hostOnly = builtins.copy();
    for (final MapEntry<String, Object?> entry in hostClients.entries) {
      hostOnly.merge(entry.key, entry.value, '\$.clients.${entry.key}', 'host');
    }
    final Map<String, String> hostLabels = hostOnly.labelsAddedTo(builtins);

    final List<ExtensionProblem> problems = <ExtensionProblem>[];
    final List<_Extension> candidates = <_Extension>[];
    for (final ExtensionFile file in extensions) {
      if (file.text == null) {
        problems.add(ExtensionProblem(file.name, file.error!));
        continue;
      }
      try {
        final _Extension? extension = _Extension.parse(file, builtins);
        if (extension == null) continue;
        final String? taken = extension.labels
            .where(
              (label) => (hostLabels[label] ?? extension.id) != extension.id,
            )
            .firstOrNull;
        if (taken != null) {
          _fail(
            r'$',
            '"$taken" already identifies "${hostLabels[taken]}" in the host '
                'configuration.',
          );
        }
        candidates.add(extension);
      } on SessionLaunchException catch (error) {
        problems.add(ExtensionProblem(file.name, error.message));
      }
    }
    // Two files claiming one label are both skipped, so the result never
    // depends on file order.
    final Map<String, List<String>> owners = <String, List<String>>{};
    for (final _Extension extension in candidates) {
      for (final String label in extension.labels) {
        (owners[label] ??= <String>[]).add(extension.file);
      }
    }
    final _Builder builder = builtins.copy();
    for (final _Extension extension in candidates) {
      final String? shared = extension.labels
          .where((label) => owners[label]!.length > 1)
          .firstOrNull;
      if (shared != null) {
        final String other = owners[shared]!.firstWhere(
          (file) => file != extension.file,
        );
        problems.add(
          ExtensionProblem(
            extension.file,
            r'$: '
            '"$shared" is also claimed by $other; both files are skipped.',
          ),
        );
        continue;
      }
      builder.merge(
        extension.id,
        extension.client,
        r'$',
        'extension',
        file: extension.file,
      );
    }
    for (final MapEntry<String, Object?> entry in hostClients.entries) {
      builder.merge(entry.key, entry.value, '\$.clients.${entry.key}', 'host');
    }
    return LauncherConfig._(
      preferences,
      Map<String, ClientDefinition>.unmodifiable(builder.clients),
      Map<String, String>.unmodifiable(builder.aliases),
      List<ExtensionProblem>.unmodifiable(problems),
    );
  }

  /// Host-wide defaults, below per-client and per-request preferences.
  final LaunchPreferences preferences;
  final Map<String, ClientDefinition> _clients;
  final Map<String, String> _aliases;

  /// Extension files that were skipped, for display in a settings screen.
  final List<ExtensionProblem> extensionErrors;

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

/// One extension file that is valid on top of the built-in catalog.
final class _Extension {
  _Extension._(this.file, this.id, this.client, this.labels);

  /// Null for a file that only describes how to install into a client; the
  /// installer reads its `install` section.
  static _Extension? parse(ExtensionFile source, _Builder builtins) {
    final String file = source.name!;
    final String id = file.endsWith('.json')
        ? file.substring(0, file.length - '.json'.length)
        : '';
    if (!_clientId.hasMatch(id)) {
      _fail(
        r'$',
        'the file name must be a client ID: lowercase letters, digits and '
            'hyphens (at most 64 characters) followed by .json.',
      );
    }
    final Map<String, Object?> json = _object(
      _decode(source.text!, r'$', 'the file is not valid JSON.'),
      r'$',
    );
    if (json['schemaVersion'] != 1) {
      _fail(r'$.schemaVersion', 'must be 1.');
    }
    final Map<String, Object?> client = <String, Object?>{
      for (final MapEntry<String, Object?> entry in json.entries)
        if (entry.key != r'$schema' &&
            entry.key != 'schemaVersion' &&
            entry.key != 'install')
          entry.key: entry.value,
    };
    if (client.isEmpty && json.containsKey('install')) return null;
    final _Builder trial = builtins.copy()
      ..merge(id, client, r'$', 'extension', file: file);
    return _Extension._(
      file,
      id,
      client,
      trial.labelsAddedTo(builtins).keys.toSet(),
    );
  }

  final String file;
  final String id;
  final Map<String, Object?> client;

  /// Source labels this file adds to the catalog, including a new ID.
  final Set<String> labels;
}

final class _Builder {
  _Builder._(this.clients, this.aliases, this.catalogLaunch);

  /// The built-in catalog, which is the only layer that may mark a client
  /// `ambiguous`.
  factory _Builder.builtins() {
    final builder = _Builder._(
      <String, ClientDefinition>{},
      <String, String>{},
      <String, LaunchSpec?>{},
    );
    for (final MapEntry<String, Object?> entry in builtinClients.entries) {
      builder._add(
        entry.key,
        entry.value,
        'builtin.${entry.key}',
        'builtin',
        null,
      );
      builder.catalogLaunch[entry.key] = builder.clients[entry.key]!.launch;
    }
    return builder;
  }

  final Map<String, ClientDefinition> clients;
  final Map<String, String> aliases;

  /// Built-in launch definitions, which later layers may not weaken.
  final Map<String, LaunchSpec?> catalogLaunch;

  _Builder copy() => _Builder._(
    Map<String, ClientDefinition>.of(clients),
    Map<String, String>.of(aliases),
    catalogLaunch,
  );

  /// Labels present here but not in [earlier], with the client they identify.
  Map<String, String> labelsAddedTo(_Builder earlier) => <String, String>{
    for (final MapEntry<String, String> entry in aliases.entries)
      if (earlier.aliases[entry.key] != entry.value) entry.key: entry.value,
  };

  /// Merges one configured client over the current definitions.
  void merge(
    String id,
    Object? raw,
    String path,
    String origin, {
    String? file,
  }) {
    final ClientDefinition? base = clients[id];
    if (base != null && base.ambiguous) {
      _fail(
        path,
        'this label covers several surfaces and cannot be configured; '
        'configure a specific client instead.',
      );
    }
    if (base == null && aliases.containsKey(id)) {
      _fail(path, 'the ID is already a source label of another client.');
    }
    _add(id, raw, path, origin, file);
  }

  /// Validates the whole entry before changing anything.
  void _add(String id, Object? raw, String path, String origin, String? file) {
    final bool catalog = origin == 'builtin';
    final ClientDefinition? base = clients[id];
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
    final LaunchSpec? launch = json.containsKey('launch')
        ? _launch(
            json['launch'],
            '$path.launch',
            inherit: base != null && base.builtin ? base.launch : null,
            pinned: catalogLaunch[id],
          )
        : base?.launch;
    final LaunchPreferences? preferences = json.containsKey('preferences')
        ? LaunchPreferences.fromJson(
            json['preferences'],
            path: '$path.preferences',
            code: 'invalid_configuration',
          )
        : base?.preferences;
    for (final String alias in added) {
      aliases[alias] = id;
    }
    clients[id] = ClientDefinition(
      id: id,
      name: name ?? base?.name ?? id,
      aliases: List<String>.unmodifiable(<String>{...?base?.aliases, ...added}),
      enabled: enabled as bool? ?? base?.enabled ?? true,
      builtin: base?.builtin ?? catalog,
      origin: base?.origin ?? origin,
      extensionFile: file ?? base?.extensionFile,
      ambiguous: json['ambiguous'] == true,
      launch: launch,
      preferences: preferences,
    );
  }
}

/// [inherit] supplies unset ID rules; [pinned] is the built-in definition,
/// whose kind and ID source stay fixed and whose ID format may only tighten.
LaunchSpec _launch(
  Object? raw,
  String path, {
  LaunchSpec? inherit,
  LaunchSpec? pinned,
}) {
  final Map<String, Object?> json = _object(raw, path);
  _keys(json, const {'command', 'uri', 'idFormat', 'idSource'}, path);
  if (json.containsKey('command') == json.containsKey('uri')) {
    _fail(path, 'specify exactly one of "command" or "uri".');
  }
  final String kind = json.containsKey('command') ? 'cli' : 'uri';
  IdFormat format = inherit?.idFormat ?? IdFormat.safe;
  if (json.containsKey('idFormat')) {
    final Object? value = json['idFormat'];
    format =
        IdFormat.values.where((f) => f.value == value).firstOrNull ??
        _fail(
          '$path.idFormat',
          'must be one of ${IdFormat.values.map((f) => f.value).join(', ')}.',
        );
  }
  String source = inherit?.idSource ?? 'conversationId';
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
  if (pinned != null) {
    if (pinned.kind != kind) {
      _fail(path, 'a built-in ${pinned.kind} client must keep the same kind.');
    }
    if (pinned.idSource != source) {
      _fail('$path.idSource', 'must stay ${pinned.idSource} for this client.');
    }
    if (pinned.idFormat != format && pinned.idFormat != IdFormat.safe) {
      _fail(
        '$path.idFormat',
        'must stay ${pinned.idFormat.value} for this client.',
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
    if (!_isExecutable(command.first)) {
      _fail(
        '$path.command',
        'the executable must be a program name or an absolute or ~/ path, '
            'not shell text.',
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
final RegExp _pathRoot = RegExp(r'^(?:~[\\/]|/|[A-Za-z]:[\\/])');
final RegExp _pathSegment = RegExp(r'^[A-Za-z0-9._+@ ()-]{1,255}$');
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

/// A program name on PATH, or an absolute or home-relative path whose
/// segments are plain names.
bool _isExecutable(String value) {
  if (_executable.hasMatch(value)) return true;
  final RegExpMatch? root = _pathRoot.firstMatch(value);
  if (root == null || value.length > 1024) return false;
  return value
      .substring(root.end)
      .split(RegExp(r'[\\/]'))
      .every((s) => _pathSegment.hasMatch(s) && s != '.' && s != '..');
}

Object? _decode(String text, String path, String reason) {
  try {
    return jsonDecode(text);
  } on FormatException {
    _fail(path, reason);
  }
}

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
