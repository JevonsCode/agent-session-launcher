import 'dart:io';

import 'config.dart';
import 'models.dart';
import 'platform.dart';

/// Plans and opens interactive sessions; it never sends a prompt or runs a model.
final class SessionLauncher {
  SessionLauncher({
    LauncherConfig? config,
    String? operatingSystem,
    ProcessRunner? processRunner,
    String? homeDirectory,
  }) : config = config ?? LauncherConfig.defaults,
       _operatingSystem = operatingSystem ?? Platform.operatingSystem,
       _processRunner = processRunner ?? runProcess,
       _homeDirectory =
           homeDirectory ??
           Platform.environment[(operatingSystem ?? Platform.operatingSystem) ==
                   'windows'
               ? 'USERPROFILE'
               : 'HOME'];

  final LauncherConfig config;
  final String _operatingSystem;
  final ProcessRunner _processRunner;

  /// Expands a `~/` executable configured by the user.
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
        ),
  ];

  bool supportsOpening(LaunchPlan plan) =>
      supportsOpeningOn(_operatingSystem, plan.kind);

  /// Validates the target and returns the fixed plan without starting anything.
  LaunchPlan inspect(SessionTarget target) {
    final ClientDefinition? client = config.client(
      target.client.trim().toLowerCase(),
    );
    final LaunchSpec? launch = client?.launch;
    if (client == null || launch == null) {
      throw const SessionLaunchException(
        'unsupported_client',
        'This client surface does not have a verified opening method.',
      );
    }
    if (!client.enabled) {
      throw const SessionLaunchException(
        'client_disabled',
        'The host has disabled opening this client.',
      );
    }
    final String id = launch.idFormat.check(
      launch.idSource == 'hostSessionId'
          ? target.hostSessionId
          : target.conversationId,
    );
    final LaunchPlan plan = launch.plan(
      id,
      workspacePath: launch.kind == 'cli'
          ? _validWorkspace(target.workspacePath, _operatingSystem)
          : null,
    );
    final String? executable = plan.executable;
    if (executable == null || !RegExp(r'^~[\\/]').hasMatch(executable)) {
      return plan;
    }
    final String home = (_homeDirectory ?? '').replaceAll(
      RegExp(r'[\\/]+$'),
      '',
    );
    if (home.isEmpty) {
      throw const SessionLaunchException(
        'unsupported_platform',
        'The home directory for this executable is unknown.',
      );
    }
    final String rest = executable.substring(1);
    return LaunchPlan(
      kind: plan.kind,
      executable:
          home +
          (_operatingSystem == 'windows' ? rest.replaceAll('/', r'\') : rest),
      arguments: plan.arguments,
      workspacePath: plan.workspacePath,
    );
  }

  /// Completion means the OS accepted the launch request, not that the client
  /// logged in or resumed successfully. [preferences] override the client's
  /// and host's configured preferences.
  Future<void> open(
    SessionTarget target, {
    LaunchPreferences? preferences,
  }) async {
    final LaunchPlan plan = inspect(target);
    final LaunchPreferences resolved =
        (preferences ?? const LaunchPreferences())
            .over(
              config.client(target.client.trim().toLowerCase())?.preferences,
            )
            .over(config.preferences);
    await openPlan(
      plan,
      operatingSystem: _operatingSystem,
      preferences: resolved,
      processRunner: _processRunner,
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
