import { requestLauncher } from '../../bindings/node/index.mjs';

const executable = process.env.AGENT_SESSION_LAUNCHER_BIN;
if (!executable) throw new Error('Set AGENT_SESSION_LAUNCHER_BIN to an absolute executable path.');
const result = await requestLauncher(executable, {
  version: 1,
  action: 'inspect',
  target: {
    client: 'pi',
    conversationId: 'a45cce14-b0be-4aea-a8f9-e88195674770',
    workspacePath: process.platform === 'win32' ? 'C:\\workspace' : '/workspace',
  },
});
process.stdout.write(`${JSON.stringify(result)}\n`);
