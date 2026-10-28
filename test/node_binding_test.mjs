import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtemp, writeFile, chmod, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { requestLauncher } from '../bindings/node/index.mjs';

const binary = process.env.AGENT_SESSION_LAUNCHER_BIN;
if (!binary) throw new Error('Set AGENT_SESSION_LAUNCHER_BIN to the compiled executable.');

test('Node host classifies a Claude Desktop session', async () => {
  const response = await requestLauncher(binary, {
    version: 1, action: 'classify', source: 'Claude Code', claudeEntrypoint: 'claude-desktop',
  });
  assert.deepEqual(response, { version: 1, ok: true, client: 'claude-desktop' });
});

test('Node host inspects an exact Pi session without launching a client', async () => {
  const response = await requestLauncher(binary, {
    version: 1, action: 'inspect', target: {
      client: 'pi', conversationId: 'a45cce14-b0be-4aea-a8f9-e88195674770',
      workspacePath: process.platform === 'win32' ? 'C:\\workspace' : '/workspace',
    },
  });
  assert.equal(response.ok, true);
  assert.equal(response.plan.executable, 'pi');
  assert.deepEqual(response.plan.arguments, ['--session', 'a45cce14-b0be-4aea-a8f9-e88195674770']);
});

test('Node host receives a structured error for an unsupported target', async () => {
  const response = await requestLauncher(binary, {
    version: 1, action: 'inspect', target: { client: 'opencode', conversationId: 'ses_1', workspacePath: '/workspace' },
  });
  assert.equal(response.ok, false);
  assert.equal(response.error.code, 'unsupported_client');
});

test('Node host rejects invalid executable paths and oversized requests', async () => {
  await assert.rejects(() => requestLauncher('relative', { version: 1, action: 'classify', source: 'Pi' }), /absolute/);
  await assert.rejects(() => requestLauncher(binary, { version: 1, action: 'classify', source: 'x'.repeat(70000) }), /large/);
});

test('Node host times out without retrying an uncertain open', async () => {
  if (process.platform === 'win32') return;
  const directory = await mkdtemp(join(tmpdir(), 'agent-launch-timeout-'));
  const fake = join(directory, 'waiting-launcher');
  try {
    await writeFile(fake, '#!/usr/bin/env node\nsetTimeout(() => {}, 30000);\n');
    await chmod(fake, 0o755);
    await assert.rejects(() => requestLauncher(fake, { version: 1, action: 'open' }, { timeoutMs: 50 }),
      error => error.code === 'unknown_outcome');
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
