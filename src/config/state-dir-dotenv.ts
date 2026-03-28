import fs from "node:fs";
import path from "node:path";
import dotenv from "dotenv";
import {
  isDangerousHostEnvOverrideVarName,
  isDangerousHostEnvVarName,
  normalizeEnvVarKey,
} from "../infra/host-env-security.js";
import { collectConfigServiceEnvVars } from "./config-env-vars.js";
import { resolveStateDir } from "./paths.js";
import type { OpenClawConfig } from "./types.js";

function isBlockedServiceEnvVar(key: string): boolean {
  return isDangerousHostEnvVarName(key) || isDangerousHostEnvOverrideVarName(key);
}

/**
 * Read and parse `~/.openclaw/.env` (or `$OPENCLAW_STATE_DIR/.env`), returning
 * a filtered record of key-value pairs suitable for embedding in a service
 * environment (LaunchAgent plist, systemd unit, Scheduled Task).
 */
export function readStateDirDotEnvVars(
  env: Record<string, string | undefined>,
): Record<string, string> {
  const stateDir = resolveStateDir(env as NodeJS.ProcessEnv);
  const dotEnvPath = path.join(stateDir, ".env");

  let content: string;
  try {
    content = fs.readFileSync(dotEnvPath, "utf8");
  } catch {
    return {};
  }

  const parsed = dotenv.parse(content);
  const entries: Record<string, string> = {};
  for (const [rawKey, value] of Object.entries(parsed)) {
    if (!value?.trim()) {
      continue;
    }
    const key = normalizeEnvVarKey(rawKey, { portable: true });
    if (!key) {
      continue;
    }
    if (isBlockedServiceEnvVar(key)) {
      continue;
    }
    entries[key] = value;
  }
  return entries;
}

/**
 * Durable service env sources survive beyond the invoking shell and are safe to
 * persist into gateway install metadata.
 *
 * Precedence:
 * 1. state-dir `.env` file vars
 * 2. config service env vars
 */
export function collectDurableServiceEnvVars(params: {
  env: Record<string, string | undefined>;
  config?: OpenClawConfig;
}): Record<string, string> {
  const entries = {
    ...readStateDirDotEnvVars(params.env),
    ...collectConfigServiceEnvVars(params.config),
  };

  // Keep launchd/systemd service env compatible with legacy z-ai key naming.
  if (!entries.ZAI_API_KEY?.trim() && entries.Z_AI_API_KEY?.trim()) {
    entries.ZAI_API_KEY = entries.Z_AI_API_KEY;
  }

  return entries;
}
