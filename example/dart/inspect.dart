import 'dart:io';

import 'package:agent_session_launcher/agent_session_launcher.dart';

void main() {
  final launcher = SessionLauncher();
  final plan = launcher.inspect(
    SessionTarget(
      client: 'pi',
      conversationId: 'a45cce14-b0be-4aea-a8f9-e88195674770',
      workspacePath: Platform.isWindows ? r'C:\workspace' : '/workspace',
    ),
  );
  stdout.writeln(plan.toJson());
}
