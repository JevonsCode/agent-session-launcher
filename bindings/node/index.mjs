import { spawn } from 'node:child_process';
import { isAbsolute } from 'node:path';

const MAX_BYTES = 65536;

/**
 * Bind the native executable and a trusted config file once, then call
 * `classify`, `clients`, `inspect` and `open`. Failed responses reject with an
 * Error whose `code` is the launcher error code.
 */
export function createLauncher({ executable, configPath, timeoutMs = 8000 } = {}) {
  const options = { configPath, timeoutMs };
  async function call(request) {
    const result = await requestLauncher(executable, { version: 1, ...request }, options);
    if (!result.ok) throw bindingError(result.error.code, result.error.message);
    return result;
  }
  return {
    classify: async (source, { claudeEntrypoint } = {}) => (await call({
      action: 'classify', source, ...(claudeEntrypoint === undefined ? {} : { claudeEntrypoint }),
    })).client,
    clients: async () => (await call({ action: 'clients' })).clients,
    inspect: async target => {
      const { plan, openSupported } = await call({ action: 'inspect', target });
      return { plan, openSupported };
    },
    /** Only for an explicit user action. Do not retry on `unknown_outcome`. */
    open: async (target, preferences) => (await call({
      action: 'open', target, ...(preferences === undefined ? {} : { preferences }),
    })).status,
  };
}

/** Call the bundled native executable. The caller authorizes `open`; no shell is used. */
export async function requestLauncher(executable, request, { timeoutMs = 8000, configPath } = {}) {
  if (typeof executable !== 'string' || !isAbsolute(executable)) {
    throw bindingError('invalid_executable', 'The launcher executable path must be absolute.');
  }
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 60000) {
    throw bindingError('invalid_timeout', 'The timeout must be between 1 and 60000 ms.');
  }
  if (configPath !== undefined && (typeof configPath !== 'string' || !isAbsolute(configPath))) {
    throw bindingError('invalid_configuration', 'The trusted configuration path must be absolute.');
  }
  let input;
  try { input = JSON.stringify(request); } catch { throw bindingError('invalid_request', 'The request is not JSON.'); }
  if (typeof input !== 'string' || Buffer.byteLength(input) > MAX_BYTES) {
    throw bindingError('invalid_request', 'The request is too large or is not JSON.');
  }
  return new Promise((resolve, reject) => {
    const args = configPath === undefined ? [] : ['--config', configPath];
    const child = spawn(executable, args, { shell: false, windowsHide: true, stdio: ['pipe', 'pipe', 'ignore'] });
    const chunks = [];
    let bytes = 0;
    let done = false;
    const timer = setTimeout(() => finish(bindingError('unknown_outcome', 'The launcher timed out; do not automatically retry an open.'), true), timeoutMs);
    function finish(error, kill = false, value) {
      if (done) return;
      done = true;
      clearTimeout(timer);
      if (kill) child.kill();
      if (error) reject(error); else resolve(value);
    }
    child.on('error', () => finish(bindingError('unavailable', 'The launcher executable could not start.')));
    child.stdout.on('data', chunk => {
      bytes += chunk.length;
      if (bytes > MAX_BYTES) finish(bindingError('invalid_response', 'The launcher response is too large.'), true);
      else chunks.push(chunk);
    });
    child.on('close', code => {
      if (done) return;
      let result;
      try { result = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
      catch { return finish(bindingError('invalid_response', 'The launcher did not return JSON.')); }
      if (!result || result.version !== 1 || typeof result.ok !== 'boolean' || (code !== 0 && result.ok)) {
        return finish(bindingError('invalid_response', 'The launcher returned an invalid response.'));
      }
      finish(null, false, result);
    });
    child.stdin.on('error', () => {});
    child.stdin.end(input);
  });
}

function bindingError(code, message) {
  return Object.assign(new Error(message), { code });
}
