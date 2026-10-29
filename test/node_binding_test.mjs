import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtemp, writeFile, chmod, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createLauncher, defaultExtensionsDirectory, requestLauncher } from '../bindings/node/index.mjs';

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

test('Node host opts in to a trusted incremental configuration file', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'agent-launch-config-'));
  try {
    const config = join(directory, 'agents.json');
    const definition = { schemaVersion: 1, clients: {
      'example-cli': { aliases: ['Example CLI'], launch: { command: ['example', '--resume', '{id}'] } },
    } };
    await writeFile(config, JSON.stringify(definition));
    const custom = await requestLauncher(binary, { version: 1, action: 'classify', source: 'Example CLI' }, { configPath: config });
    assert.equal(custom.client, 'example-cli');
    const builtin = await requestLauncher(binary, { version: 1, action: 'classify', source: 'Pi' }, { configPath: config });
    assert.equal(builtin.client, 'pi');
    definition.clients['example-cli'].launch.command = ['example', '--continue', '{id}'];
    await writeFile(config, JSON.stringify(definition));
    const reloaded = await requestLauncher(binary, { version: 1, action: 'inspect', target: {
      client: 'example-cli', conversationId: 'session-42',
      workspacePath: process.platform === 'win32' ? 'C:\\workspace' : '/workspace',
    } }, { configPath: config });
    assert.deepEqual(reloaded.plan.arguments, ['--continue', 'session-42']);
    await assert.rejects(() => requestLauncher(binary, { version: 1, action: 'classify', source: 'Pi' }, { configPath: 'relative' }), /absolute/);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
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

test('createLauncher binds the executable and config for every call', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'agent-launch-facade-'));
  try {
    const configPath = join(directory, 'launcher.json');
    await writeFile(configPath, JSON.stringify({
      schemaVersion: 1,
      preferences: { macosTerminal: 'iterm' },
      clients: { cursor: { enabled: false }, 'example-cli': { name: 'Example', launch: { command: ['example', '--resume', '{id}'] } } },
    }));
    const launcher = createLauncher({ executable: binary, configPath });
    assert.equal(await launcher.classify('Claude Code', { claudeEntrypoint: 'claude-desktop' }), 'claude-desktop');
    const { clients, extensionErrors } = await launcher.clients();
    assert.deepEqual(extensionErrors, []);
    assert.equal(clients.find(c => c.id === 'cursor').enabled, false);
    assert.equal(clients.find(c => c.id === 'example-cli').name, 'Example');
    const { plan } = await launcher.inspect({
      client: 'example-cli', conversationId: 'session-7',
      workspacePath: process.platform === 'win32' ? 'C:\\workspace' : '/workspace',
    });
    assert.deepEqual(plan.arguments, ['--resume', 'session-7']);
    await assert.rejects(() => launcher.inspect({ client: 'cursor', conversationId: 'bc-1' }),
      error => error.code === 'client_disabled');
    await writeFile(configPath, '{"schemaVersion":1,"clients":{"opencode":{}}}');
    await assert.rejects(() => launcher.clients(),
      error => error.code === 'invalid_configuration' && error.message.startsWith('$.clients.opencode:'));
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('createLauncher reads hand-written extension files and reports bad ones', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'agent-launch-extensions-'));
  try {
    await writeFile(join(directory, 'acme-agent.json'), JSON.stringify({
      schemaVersion: 1, name: 'Acme Agent', aliases: ['Acme Agent CLI'],
      launch: { command: ['acme-agent', 'resume', '{id}'] },
    }));
    await writeFile(join(directory, 'broken.json'), '{"schemaVersion":1,"launch":{"command":["broken"]}}');
    const launcher = createLauncher({ executable: binary, extensionsDir: directory });
    assert.equal(await launcher.classify('Acme Agent CLI'), 'acme-agent');
    const { clients, extensionErrors } = await launcher.clients();
    const acme = clients.find(c => c.id === 'acme-agent');
    assert.equal(acme.origin, 'extension');
    assert.equal(acme.extensionFile, 'acme-agent.json');
    assert.equal(extensionErrors.length, 1);
    assert.equal(extensionErrors[0].file, 'broken.json');
    assert.match(extensionErrors[0].message, /^\$\.launch\.command:/);
    assert.ok(!JSON.stringify(extensionErrors).includes(directory));
    await assert.rejects(() => createLauncher({ executable: binary, extensionsDir: 'relative' }).clients(),
      error => error.code === 'invalid_configuration');
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('defaultExtensionsDirectory follows each platform convention', () => {
  assert.equal(defaultExtensionsDirectory({ HOME: '/Users/a' }, 'darwin'), '/Users/a/.config/agent-session-launcher/clients');
  assert.equal(defaultExtensionsDirectory({ HOME: '/home/a', XDG_CONFIG_HOME: '/x' }, 'linux'), '/x/agent-session-launcher/clients');
  assert.equal(defaultExtensionsDirectory({ APPDATA: 'C:\\Users\\a\\AppData\\Roaming' }, 'win32'),
    'C:\\Users\\a\\AppData\\Roaming\\agent-session-launcher\\clients');
  assert.equal(defaultExtensionsDirectory({}, 'linux'), undefined);
});
