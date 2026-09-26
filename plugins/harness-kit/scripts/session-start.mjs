#!/usr/bin/env node
// SessionStart hook: announce the plugin and its version.
// The version is read from plugin.json so the two can never disagree.
import { readFileSync } from "node:fs";

const manifest = JSON.parse(
  readFileSync(new URL("../.claude-plugin/plugin.json", import.meta.url), "utf8"),
);

console.log(`harness-kit ${manifest.version} loaded`);
process.exit(0);
