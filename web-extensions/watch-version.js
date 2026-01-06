#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const chokidar = require('chokidar');

const watchDir = __dirname;

// Track last known access time for each file
// This helps us detect if http-server has read the file
const lastAccessTimes = new Map();
const lastVersionUpdateTimes = new Map();

// Initialize access times for all JS files on startup
function initializeAccessTimes() {
  const files = fs.readdirSync(watchDir).filter(f => f.endsWith('.js'));
  files.forEach(file => {
    try {
      const fullPath = path.join(watchDir, file);
      const stats = fs.statSync(fullPath);
      lastAccessTimes.set(file, stats.atimeMs);
      lastVersionUpdateTimes.set(file, stats.atimeMs);
    } catch (error) {
      // Ignore errors for files we can't stat
    }
  });
}

// Check if file was accessed since last version update
function wasFileAccessed(filePath) {
  try {
    const fullPath = path.join(watchDir, filePath);
    const stats = fs.statSync(fullPath);
    const currentAccessTime = stats.atimeMs;
    const lastKnownAccessTime = lastAccessTimes.get(filePath) || 0;

    // Allow small tolerance (100ms) for timing differences
    const tolerance = 100;
    const wasAccessed = currentAccessTime > (lastKnownAccessTime + tolerance);

    return wasAccessed;
  } catch (error) {
    console.error(`Error checking access time for ${filePath}:`, error.message);
    return false;
  }
}

// Increment patch version
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
      console.error(`Invalid patch version: ${parts[2]}`);
      return version;
    }
    return `${parts[0]}.${parts[1]}.${patch + 1}`;
  }

  console.error(`Invalid version format: ${version}`);
  return version;
}

// Update version in a JS file
function updateVersionInFile(filePath) {
  const fullPath = path.join(watchDir, filePath);

  try {
    // Check if file was accessed since last version update
    if (wasFileAccessed(filePath)) {
      console.log(`${filePath}: Skipping version update - file was accessed by http-server`);
      // Update the last known access time to current
      const stats = fs.statSync(fullPath);
      lastAccessTimes.set(filePath, stats.atimeMs);
      return;
    }

    let content = fs.readFileSync(fullPath, 'utf8');
    const lines = content.split('\n');

    // Find and update the @version line
    let updated = false;
    const versionRegex = /^(\s*\/\/\s*@version\s+)(.+)$/;

    const updatedLines = lines.map((line) => {
      const match = line.match(versionRegex);
      if (match) {
        const oldVersion = match[2].trim();
        const newVersion = incrementPatchVersion(oldVersion);
        updated = true;
        console.log(`${filePath}: Version updated ${oldVersion} -> ${newVersion}`);
        return `${match[1]}${newVersion}`;
      }
      return line;
    });

    if (updated) {
      fs.writeFileSync(fullPath, updatedLines.join('\n'), 'utf8');

      // Update access time tracking after version update
      const stats = fs.statSync(fullPath);
      lastAccessTimes.set(filePath, stats.atimeMs);
      lastVersionUpdateTimes.set(filePath, Date.now());
    } else {
      console.warn(`${filePath}: No @version line found`);
    }
  } catch (error) {
    console.error(`Error updating ${filePath}:`, error.message);
  }
}

// Initialize access times on startup
initializeAccessTimes();

// Watch for changes
const watcher = chokidar.watch('*.js', {
  cwd: watchDir,
  ignored: /node_modules/,
  persistent: true,
  ignoreInitial: true
});

let debounceTimers = new Map();
const DEBOUNCE_MS = 500; // Wait 500ms after last change before updating

watcher.on('change', (filePath) => {
  console.log(`File changed: ${filePath}`);

  // Debounce per file: clear previous timer for this file and set a new one
  const existingTimer = debounceTimers.get(filePath);
  if (existingTimer) {
    clearTimeout(existingTimer);
  }

  const timer = setTimeout(() => {
    updateVersionInFile(filePath);
    debounceTimers.delete(filePath);
  }, DEBOUNCE_MS);

  debounceTimers.set(filePath, timer);
});

watcher.on('error', (error) => {
  console.error('Watcher error:', error);
});

console.log('Watching JS files for changes...');
console.log('Press Ctrl+C to stop.');
