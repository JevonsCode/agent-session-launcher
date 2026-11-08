import 'dart:io';

import 'config.dart';
import 'models.dart';
import 'platform.dart';

/// Plans and opens interactive sessions. It never runs a model or talks to an
/// Agent: a new session's prompt is handed to the client as one argument or
/// one URI value, and the client decides what to do with it.
final class SessionLauncher {
  SessionLauncher({
    LauncherConfig? config,
    String? operatingSystem,
    ProcessRunner? processRunner,
    DetachedStarter? detachedStarter,
    String? homeDirectory,
    CommandLookup? commandAvailable,
  }) : config = config ?? LauncherConfig.defaults,
       _operatingSystem = operatingSystem ?? Platform.operatingSystem,
       _processRunner = processRunner ?? runProcess,
       _detachedStarter = detachedStarter ?? startDetached,
       _commandAvailable = commandAvailable ?? isOnPath,
       _homeDirectory =
           homeDirectory ??
           Platform.environment[(operatingSystem ?? Platform.operatingSystem) ==
                   'windows'
               ? 'USERPROFILE'
               : 'HOME'];

  final LauncherConfig config;
  final String _operatingSystem;
  final ProcessRunner _processRunner;

  /// Starts a Linux terminal window, which keeps running on its own.
  final DetachedStarter _detachedStarter;

  /// Decides which terminal program can open a CLI plan.
  final CommandLookup _commandAvailable;

  /// Expands a `~/` executable configured by the user, and is where a new
  /// CLI session starts without a workspace.
  final String? _homeDirectory;

  String classify(String source, {String? claudeEntrypoint}) =>
      config.classify(source, claudeEntrypoint: claudeEntrypoint);

  /// Specific clients for a settings screen; ambiguous labels are omitted.
  List<ClientInfo> clients() => <ClientInfo>[
    for (final ClientDefinition client in config.clients)
      if (!client.ambiguous)
        ClientInfo(
          id: client.id,
          name: client.name,
          enabled: client.enabled,
          builtin: client.builtin,
          origin: client.origin,
          extensionFile: client.extensionFile,
          kind: client.launch?.kind,
          idSource: client.launch?.idSource,
          idFormat: client.launch?.idFormat.value,
          openSupported:
              client.launch != null &&
              supportsOpeningOn(_operatingSystem, client.launch!.kind),
          newSession: client.newSession == null
              ? null
              : NewSessionInfo(
                  kind: client.newSession!.kind,
                  prompt: client.newSession!.prompt,
                  openSupported: supportsOpeningOn(
                    _operatingSystem,
                    client.newSession!.kind,
                  ),
                ),
        ),
  ];

  bool supportsOpening(LaunchPlan plan) =>
      supportsOpeningOn(_operatingSystem, plan.kind);

  /// Validates the target and returns the fixed plan without starting anything.
  LaunchPlan inspect(SessionTarget target) {
    final ClientDefinition client = _enabledClient(target.client);
    final LaunchSpec? launch = client.launch;
    if (launch == null) throw _unsupported;
    final String id = launch.idFormat.check(
      launch.idSource == 'hostSessionId'
          ? target.hostSessionId
          : target.conversationId,
    );
    return _withOpener(
      _expandHome(
        launch.plan(
          id,
          workspacePath: launch.kind == 'cli'
              ? _validWorkspace(target.workspacePath, _operatingSystem)
              : null,
        ),
      ),
    );
  }

  /// Validates a new-session target and returns its fixed plan without
  /// starting anything.
  LaunchPlan inspectNew(NewSessionTarget target) {
    final ClientDefinition client = _enabledClient(target.client);
    final NewSessionSpec? spec = client.newSession;
    if (spec == null) throw _unsupported;
    final String? prompt = target.prompt;
    if (prompt != null) {
      if (spec.prompt == null) {
        throw const SessionLaunchException(
          'unsupported_prompt',
          'This client cannot take a prompt when it opens a new session.',
        );
      }
      checkPrompt(prompt, cli: spec.kind == 'cli');
    }
    final String? environment = target.environment;
    if (environment != null &&
        (environment != RunEnvironment.wsl ||
            _operatingSystem != 'windows' ||
            spec.kind != 'cli')) {
      throw const SessionLaunchException(
        'invalid_target',
        'Only a CLI on Windows can run in WSL.',
      );
    }
    if (spec.kind == 'uri') return spec.plan(prompt);
    final String? workspace = target.workspacePath == null
        ? null
        : _validWorkspace(target.workspacePath, _operatingSystem);
    if (environment == RunEnvironment.wsl) {
      return _withOpener(
        wslPlan(
          spec.plan(prompt),
          linuxDirectory: workspace,
          windowsDirectory: _home(),
        ),
      );
    }
    return _withOpener(
      _expandHome(spec.plan(prompt, workspacePath: workspace ?? _home())),
    );
  }

  ClientDefinition _enabledClient(String id) {
    final ClientDefinition? client = config.client(id.trim().toLowerCase());
    if (client == null) throw _unsupported;
    if (!client.enabled) {
      throw const SessionLaunchException(
        'client_disabled',
        'The host has disabled opening this client.',
      );
    }
    return client;
  }

  static const SessionLaunchException _unsupported = SessionLaunchException(
    'unsupported_client',
    'This client surface does not have a verified opening method.',
  );

  LaunchPlan _withOpener(LaunchPlan plan) {
    if (plan.kind != 'cli') return plan;
    if (_operatingSystem == 'windows') {
      return plan.withOpener(
        _commandAvailable('wt.exe')
            ? WindowsOpener.windowsTerminal
            : WindowsOpener.powershell,
      );
    }
    if (_operatingSystem == 'linux') {
      return plan.withOpener(
        linuxTerminalPrograms.where(_commandAvailable).firstOrNull,
      );
    }
    return plan;
  }

  String _home() {
    final String home = (_homeDirectory ?? '').replaceAll(
      RegExp(r'[\\/]+$'),
      '',
    );
    if (home.isEmpty) {
      throw const SessionLaunchException(
        'unsupported_platform',
        'The home directory is unknown.',
      );
    }
    return home;
  }

  LaunchPlan _expandHome(LaunchPlan plan) {
    final String? executable = plan.executable;
    if (executable == null || !RegExp(r'^~[\\/]').hasMatch(executable)) {
      return plan;
    }
    final String rest = executable.substring(1);
    return LaunchPlan(
      kind: plan.kind,
      executable:
          _home() +
          (_operatingSystem == 'windows' ? rest.replaceAll('/', r'\') : rest),
      arguments: plan.arguments,
      workspacePath: plan.workspacePath,
      newSession: plan.newSession,
      prompt: plan.prompt,
      environment: plan.environment,
    );
  }

  /// Completion means the OS accepted the launch request, not that the client
  /// logged in or resumed successfully. [preferences] override the client's
  /// and host's configured preferences.
  Future<void> open(SessionTarget target, {LaunchPreferences? preferences}) =>
      _open(inspect(target), target.client, preferences);

  /// Opens a new session. Completion means the OS accepted the launch
  /// request, not that the client started or received the prompt.
  Future<void> openNew(
    NewSessionTarget target, {
    LaunchPreferences? preferences,
  }) => _open(inspectNew(target), target.client, preferences);

  Future<void> _open(
    LaunchPlan plan,
    String client,
    LaunchPreferences? preferences,
  ) async {
    final LaunchPreferences resolved =
        (preferences ?? const LaunchPreferences())
            .over(config.client(client.trim().toLowerCase())?.preferences)
            .over(config.preferences);
    await openPlan(
      plan,
      operatingSystem: _operatingSystem,
      preferences: resolved,
      processRunner: _processRunner,
      detachedStarter: _detachedStarter,
    );
  }
}

/// The longest prompt accepted, in UTF-16 code units. Every opener fits it
/// within Windows' 32,767-character command line.
const int maxPromptLength = 2000;

/// Refuses a prompt no opener can carry as plain data. A CLI prompt may not
/// begin with `-`, which the client would read as an option.
void checkPrompt(String prompt, {required bool cli}) {
  if (prompt.trim().isEmpty ||
      prompt.length > maxPromptLength ||
      prompt.contains(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]')) ||
      (cli && prompt.startsWith('-'))) {
    throw const SessionLaunchException(
      'invalid_prompt',
      'The prompt must be 1 to 2000 characters of text without control '
          'characters other than tabs and line breaks; a CLI prompt may not '
          'begin with "-".',
    );
  }
}

String _validWorkspace(String? value, String operatingSystem) {
  final String workspace = value ?? '';
  final bool absolute = operatingSystem == 'windows'
      ? RegExp(r'^[A-Za-z]:[\\/]').hasMatch(workspace) ||
            RegExp(r'^\\\\[^\\/]+[\\/][^\\/]+(?:[\\/]|$)').hasMatch(workspace)
      : workspace.startsWith('/');
  if (!absolute ||
      workspace != workspace.trim() ||
      workspace.length > 4096 ||
      workspace.contains(RegExp(r'[\x00\r\n]'))) {
    throw const SessionLaunchException(
      'invalid_target',
      'An absolute workspace path is required.',
    );
  }
  return workspace;
}
