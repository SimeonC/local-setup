#!/usr/bin/env node

import express from 'express';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';
import chokidar from 'chokidar';

const app = express();
const PORT = 9876;
const __filename = fileURLToPath(import.meta.url);
const watchDir = path.dirname(__filename);

const httpAccessTimes = new Map<string, number>();
const lastVersionUpdateTimes = new Map<string, number>();

const colors = {
  reset: '\x1b[0m',
  red: (s: string) => `\x1b[31m${s}\x1b[0m`,
  green: (s: string) => `\x1b[32m${s}\x1b[0m`,
  yellow: (s: string) => `\x1b[33m${s}\x1b[0m`,
  blue: (s: string) => `\x1b[34m${s}\x1b[0m`,
  magenta: (s: string) => `\x1b[35m${s}\x1b[0m`,
  cyan: (s: string) => `\x1b[36m${s}\x1b[0m`,
  bright: (s: string) => `\x1b[1m${s}\x1b[0m`,
  dim: (s: string) => `\x1b[2m${s}\x1b[0m`,
};

function initializeTracking() {
  const files = fs.readdirSync(watchDir).filter(f => f.endsWith('.js'));
  const now = Date.now();
  files.forEach(file => {
    httpAccessTimes.set(file, 0);
    lastVersionUpdateTimes.set(file, 0);
  });
}

function incrementPatchVersion(version) {
  const parts = version.split('.');

  // Handle versions with 2 parts (e.g., "1.0" -> "1.0.1")
  if (parts.length === 2) {
    return `${parts[0]}.${parts[1]}.1`;
  }

  // Handle versions with 3 parts (e.g., "1.4.2" -> "1.4.3")
  if (parts.length === 3) {
    const patch = parseInt(parts[2], 10);
    if (isNaN(patch)) {
      console.error(`${colors.red('[ERROR]')} Invalid patch version "${parts[2]}" in version "${version}"`);
      return version;
    }
    return `${parts[0]}.${parts[1]}.${patch + 1}`;
  }

  console.error(`${colors.red('[ERROR]')} Invalid version format: "${version}"`);
  return version;
}

function updateVersionInFile(filePath) {
  const fullPath = path.join(watchDir, filePath);

  try {
    const lastHttpAccess = httpAccessTimes.get(filePath) || 0;
    const lastVersionUpdate = lastVersionUpdateTimes.get(filePath) || 0;

    if (lastVersionUpdate && lastHttpAccess < lastVersionUpdate) {
      // Not accessed via HTTP since last update, don't update the version
      return;
    }

    let content = fs.readFileSync(fullPath, 'utf8');
    const lines = content.split('\n');

    let updated = false;
    const versionRegex = /^(\s*\/\/\s*@version\s+)(.+)$/;

    const updatedLines = lines.map((line) => {
      const match = line.match(versionRegex);
      if (match) {
        const oldVersion = match[2].trim();
        const newVersion = incrementPatchVersion(oldVersion);
        updated = true;
        console.log(`${colors.cyan('[VERSION]')} ${filePath}: ${colors.dim(oldVersion)} ${colors.green('→')} ${colors.bright(newVersion)}`);
        return `${match[1]}${newVersion}`;
      }
      return line;
    });

    if (updated) {
      fs.writeFileSync(fullPath, updatedLines.join('\n'), 'utf8');
      lastVersionUpdateTimes.set(filePath, Date.now());
    } else {
      console.warn(`${colors.yellow('[WARN]')} ${filePath}: No @version line found`);
    }
  } catch (error) {
    console.error(`${colors.red('[ERROR]')} Failed to update ${filePath}:`, error.message);
  }
}

app.get('/:fileName', (req, res, next) => {
  const fileName = req.params.fileName;

  if (!fileName.endsWith('.js')) {
    return next();
  }

  const filePath = path.join(watchDir, fileName);

  if (!fs.existsSync(filePath)) {
    return next();
  }

  httpAccessTimes.set(fileName, Date.now());
  console.log(`${colors.blue('[HTTP]')} ${fileName}`);

  res.sendFile(fileName, { root: watchDir });
});

app.use(express.static(watchDir));

const watcher = chokidar.watch(watchDir, {
  ignored: [
    /node_modules/,
    (filePath) => {
      // Don't ignore directories - chokidar needs to traverse them
      try {
        const stats = fs.statSync(filePath);
        if (stats.isDirectory()) {
          return false;
        }
      } catch {
      }
      return !filePath.endsWith('.js');
    }
  ],
  persistent: true,
  ignoreInitial: true,
  awaitWriteFinish: {
    stabilityThreshold: 100,
    pollInterval: 100
  }
});

let debounceTimers = new Map<string, NodeJS.Timeout>();
const DEBOUNCE_MS = 500;

watcher.on('change', (filePath) => {
  const relativePath = path.relative(watchDir, filePath);
  const fileName = path.basename(relativePath);

  if (!fileName.endsWith('.js')) {
    return;
  }

  const existingTimer = debounceTimers.get(fileName);
  if (existingTimer) {
    clearTimeout(existingTimer);
  }

  const timer = setTimeout(() => {
    updateVersionInFile(fileName);
    debounceTimers.delete(fileName);
  }, DEBOUNCE_MS);

  debounceTimers.set(fileName, timer);
});

watcher.on('error', (error: unknown) => {
  const err = error instanceof Error ? error : new Error(String(error));
  console.error(`${colors.red('[ERROR]')} File watcher error: ${err.message}`);
});

initializeTracking();

const server = app.listen(PORT, () => {
  console.log(`${colors.magenta('[SERVER]')} Running on ${colors.cyan(`http://localhost:${PORT}`)}`);
  console.log(`${colors.magenta('[SERVER]')} Watching JS files for changes`);
  console.log(`${colors.magenta('[SERVER]')} Press Ctrl+C to stop`);
});

async function gracefulShutdown(signal: string) {
  console.log(`\n${colors.yellow('[SHUTDOWN]')} ${signal} received, shutting down gracefully...`);

  debounceTimers.forEach((timer) => clearTimeout(timer));
  debounceTimers.clear();

  await watcher.close();
  console.log(`${colors.yellow('[SHUTDOWN]')} File watcher closed`);

  server.close(() => {
    console.log(`${colors.yellow('[SHUTDOWN]')} Server closed`);
    process.exit(0);
  });

  setTimeout(() => {
    console.error(`${colors.red('[SHUTDOWN]')} Forced shutdown after timeout`);
    process.exit(1);
  }, 10000);
}

process.on('SIGINT', () => gracefulShutdown('SIGINT'));
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));

