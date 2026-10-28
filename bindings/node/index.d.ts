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
}

export interface ClientInfo {
  id: string;
  name: string;
  enabled: boolean;
  builtin: boolean;
  /** null: identified, but no verified opening method. */
  kind: 'cli' | 'uri' | null;
  idSource?: 'conversationId' | 'hostSessionId';
  idFormat?: 'safe' | 'uuid' | 'claude-desktop' | 'cursor-background';
  requiresWorkspace: boolean;
  openSupported: boolean;
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
  timeoutMs?: number;
}

export interface Launcher {
  classify(source: string, options?: { claudeEntrypoint?: string }): Promise<string>;
  clients(): Promise<ClientInfo[]>;
  inspect(target: SessionTarget): Promise<{ plan: LaunchPlan; openSupported: boolean }>;
  /** Only for an explicit user action; never retry on `unknown_outcome`. */
  open(target: SessionTarget, preferences?: LaunchPreferences): Promise<'launch_requested'>;
}

export function createLauncher(options: LauncherOptions): Launcher;

export function requestLauncher(
  executable: string,
  request: Record<string, unknown>,
  options?: { timeoutMs?: number; configPath?: string },
): Promise<Record<string, unknown> & { version: 1; ok: boolean }>;
