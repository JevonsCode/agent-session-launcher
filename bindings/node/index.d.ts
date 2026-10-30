export interface SessionTarget {
  client: string;
  conversationId?: string;
  hostSessionId?: string;
  workspacePath?: string;
}

export interface LaunchPreferences {
  macosTerminal?: 'terminal' | 'iterm';
  itermOpenMode?: 'new-window' | 'new-tab';
}

export interface LaunchPlan {
  kind: 'cli' | 'uri';
  uri?: string;
  executable?: string;
  arguments?: string[];
  workspacePath?: string;
  /**
   * Windows CLI plans only: Windows Terminal when `wt.exe` is on PATH,
   * otherwise a new console window through Windows PowerShell.
   */
  opener?: 'windows-terminal' | 'powershell';
}

export interface ClientInfo {
  id: string;
  name: string;
  enabled: boolean;
  builtin: boolean;
  /** Where the client was first defined. */
  origin: 'builtin' | 'extension' | 'host';
  /** The user extension file that defines or customizes this client. */
  extensionFile?: string;
  /** null: identified, but no verified opening method. */
  kind: 'cli' | 'uri' | null;
  idSource?: 'conversationId' | 'hostSessionId';
  idFormat?: 'safe' | 'uuid' | 'claude-desktop' | 'cursor-background';
  requiresWorkspace: boolean;
  openSupported: boolean;
}

/** A skipped extension file; `file` is a file name, never a full path. */
export interface ExtensionProblem {
  file?: string;
  message: string;
}

/** Rejections carry the launcher or binding error code. */
export interface LauncherError extends Error {
  code: string;
}

export interface LauncherOptions {
  /** Absolute path to the native executable for this OS and CPU. */
  executable: string;
  /** Absolute path to a trusted host configuration file. */
  configPath?: string;
  /** Absolute path to the user's extension directory, usually `defaultExtensionsDirectory()`. */
  extensionsDir?: string;
  timeoutMs?: number;
}

export interface Launcher {
  classify(source: string, options?: { claudeEntrypoint?: string }): Promise<string>;
  clients(): Promise<{ clients: ClientInfo[]; extensionErrors: ExtensionProblem[] }>;
  inspect(target: SessionTarget): Promise<{ plan: LaunchPlan; openSupported: boolean }>;
  /** Only for an explicit user action; never retry on `unknown_outcome`. */
  open(target: SessionTarget, preferences?: LaunchPreferences): Promise<'launch_requested'>;
}

export function createLauncher(options: LauncherOptions): Launcher;

/** The shared per-user extension directory, or undefined without a home directory. */
export function defaultExtensionsDirectory(
  env?: Record<string, string | undefined>,
  platform?: string,
): string | undefined;

export function requestLauncher(
  executable: string,
  request: Record<string, unknown>,
  options?: { timeoutMs?: number; configPath?: string; extensionsDir?: string },
): Promise<Record<string, unknown> & { version: 1; ok: boolean }>;
