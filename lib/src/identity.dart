import 'config.dart';

String normalizeAgentSource(String source) => source
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

/// Classifies against the built-in catalog. Hosts with configuration call
/// [LauncherConfig.classify] or `SessionLauncher.classify` instead.
String classifyAgentSource(String source, {String? claudeEntrypoint}) =>
    LauncherConfig.defaults.classify(
      source,
      claudeEntrypoint: claudeEntrypoint,
    );
