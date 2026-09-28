#!/usr/bin/env node
/**
 * Peer-programming runner.
 *
 * Node built-ins only. No third-party dependencies.
 *
 * ---------------------------------------------------------------------------
 * PROCESS INTEGRATION CONTRACT (v1)
 * ---------------------------------------------------------------------------
 * Launch:
 *     node runner.mjs watch
 *
 * The host writes exactly ONE newline-terminated JSON object to the child's
 * stdin as the bootstrap request:
 *
 *     {"v":1,"id":"<sessionId>","op":"watch","root":"/abs/project",
 *      "scope":"src","controlFile":"/abs/session/control.ndjson"}
 *
 *   - `root` is the immutable project root. It is fixed for the lifetime of
 *     the process; no later message can change it.
 *   - `scope` is optional and may be a single relative path or an array of
 *     them. Absent/empty means "the whole root".
 *   - `controlFile` is a session-local path. Its parent directories are
 *     created and the file itself is created if absent.
 *
 * stdin is read exactly once, for that bootstrap line. Nothing is ever read
 * from stdin again, so a launcher that cannot write to stdin after spawn (for
 * example `$.process.spawn`) is fully supported.
 *
 * Control channel (host -> runner): the host writes versioned JSON into
 * `controlFile`. Appending NDJSON is the normal mode; rewriting the file whole
 * also works (a shrink is detected and the reader resyncs from offset 0).
 *
 *     {"v":1,"id":"c1","op":"set_scope","scope":"src/api"}
 *     {"v":1,"id":"c2","op":"discover_tests","changed":["src/api/a.ts"]}
 *     {"v":1,"id":"c3","op":"close"}
 *
 * The control file is watched *and* re-read on the 5s reconcile tick, so a
 * missed filesystem notification can delay a control message but never lose it.
 *
 * Output channel (runner -> host): NDJSON on stdout, one object per line.
 * Every line carries an `event` discriminator:
 *
 *     {"v":1,"id":"<sessionId>","event":"ready","root":...,"scope":[...],
 *      "controlFile":...,"recursive":true,"pid":1234}
 *     {"v":1,"id":"<sessionId>","event":"batch","batchId":"<sessionId>:1",
 *      "paths":["src/a.ts"],"tests":["src/a.test.ts"],"status":"failed",
 *      "output":"...","diagnostics":[{"file":"src/a.ts","line":3,...}],
 *      "changes":[{"type":"changed","path":"src/a.ts"}],"reason":"event"}
 *     {"v":1,"id":"c1","event":"response","ok":true,"op":"set_scope","result":{...}}
 *     {"v":1,"id":"c9","event":"error","code":"E_...","message":"..."}
 *     {"v":1,"id":"<sessionId>","event":"closed","reason":"close_requested"}
 *
 * `status` is one of: passed | failed | error | unresolved | no_tests.
 * It is never `passed` unless at least one step ran and exited 0 with nothing
 * left ambiguous or missing.
 *
 * stderr is reserved for fatal launch failures only.
 *
 * Exit codes: 0 normal close, 2 bad invocation / bad bootstrap message.
 * ---------------------------------------------------------------------------
 */

import { spawn as nodeSpawn } from 'node:child_process';
import { Buffer } from 'node:buffer';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';
import { StringDecoder } from 'node:string_decoder';
import { pathToFileURL } from 'node:url';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

export const PROTOCOL_VERSION = 1;

export const ERR = Object.freeze({
  MALFORMED: 'E_MALFORMED',
  VERSION: 'E_VERSION',
  DUPLICATE_ID: 'E_DUPLICATE_ID',
  UNKNOWN_OP: 'E_UNKNOWN_OP',
  CONTAINMENT: 'E_CONTAINMENT',
  ROOT_IMMUTABLE: 'E_ROOT_IMMUTABLE',
  COMMAND_NOT_ALLOWED: 'E_COMMAND_NOT_ALLOWED',
  SPAWN: 'E_SPAWN',
  TIMEOUT: 'E_TIMEOUT',
  ABORTED: 'E_ABORTED',
  CLOSED: 'E_CLOSED',
  INTERNAL: 'E_INTERNAL',
});

/** Fixed vendor / generated directories that are never watched or scanned. */
export const IGNORED_DIRS = Object.freeze(
  new Set([
    '.git',
    '.hg',
    '.svn',
    '.idea',
    '.vscode',
    'node_modules',
    'bower_components',
    'vendor',
    'dist',
    'build',
    'out',
    'coverage',
    '.next',
    '.nuxt',
    '.svelte-kit',
    '.turbo',
    '.parcel-cache',
    '.cache',
    '.yarn',
    '.pnpm-store',
    'target',
    '_build',
    'deps',
    '.elixir_ls',
    '.venv',
    'venv',
    '__pycache__',
    '.tox',
    '.mypy_cache',
    '.pytest_cache',
    '.gradle',
    'Pods',
    'DerivedData',
    '.build',
    '.swiftpm',
    '.terraform',
    '.bundle',
    'tmp',
    'log',
  ])
);

/** Bare commands the runner is ever permitted to spawn. */
export const ALLOWED_COMMANDS = Object.freeze(
  new Set(['npm', 'pnpm', 'yarn', 'bun', 'bundle', 'rspec', 'go', 'mix', 'swift'])
);

export const DEFAULT_TIMEOUT_MS = 120_000;
export const MAX_TIMEOUT_MS = 600_000;
export const DEFAULT_MAX_OUTPUT_BYTES = 1_000_000;
export const MAX_OUTPUT_BYTES = 8_000_000;
export const KILL_GRACE_MS = 2_000;
export const DEFAULT_DEBOUNCE_MS = 120;
export const RECONCILE_MS = 5_000;
export const MAX_SNAPSHOT_ENTRIES = 200_000;
export const MAX_DIAGNOSTICS = 100;

const JS_EXTS = Object.freeze(['.js', '.jsx', '.mjs', '.cjs', '.ts', '.tsx', '.mts', '.cts']);
const JS_TEST_INFIX = Object.freeze(['.test', '.spec']);

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

export class RunnerError extends Error {
  constructor(code, message, detail) {
    super(message);
    this.name = 'RunnerError';
    this.code = code;
    if (detail !== undefined) this.detail = detail;
  }
}

const malformed = (msg, detail) => new RunnerError(ERR.MALFORMED, msg, detail);
const containment = (msg, detail) => new RunnerError(ERR.CONTAINMENT, msg, detail);

// ---------------------------------------------------------------------------
// Path canonicalization / containment
// ---------------------------------------------------------------------------

function realpathBestEffort(abs) {
  const realpath = fs.realpathSync.native ?? fs.realpathSync;
  let current = abs;
  const tail = [];
  for (;;) {
    try {
      const resolved = realpath(current);
      return tail.length ? path.join(resolved, ...tail.reverse()) : resolved;
    } catch (err) {
      if (err.code !== 'ENOENT' && err.code !== 'ENOTDIR') throw err;
      const parent = path.dirname(current);
      if (parent === current) return abs;
      tail.push(path.basename(current));
      current = parent;
    }
  }
}

const toPosix = (p) => p.split(path.sep).join('/');

/** Canonicalize the immutable project root. Must be an existing absolute directory. */
export function canonicalizeRoot(root) {
  if (typeof root !== 'string' || root.length === 0) {
    throw malformed('root must be a non-empty string');
  }
  if (root.includes('\0')) throw malformed('root contains a NUL byte');
  if (!path.isAbsolute(root)) throw malformed('root must be an absolute path', { root });
  let stat;
  const abs = realpathBestEffort(path.resolve(root));
  try {
    stat = fs.statSync(abs);
  } catch (err) {
    throw malformed(`root does not exist: ${root}`, { cause: err.code });
  }
  if (!stat.isDirectory()) throw malformed(`root is not a directory: ${root}`);
  return abs;
}

/**
 * Resolve `target` strictly inside `root` (symlinks included) and, when a
 * non-empty `scope` is supplied, inside that scope too.
 * @returns {{abs: string, rel: string}} rel is POSIX and root-relative ('' === root).
 */
export function resolveWithin(root, target, scope) {
  if (typeof target !== 'string' || target.length === 0) {
    throw malformed('path must be a non-empty string', { path: target });
  }
  if (target.includes('\0')) throw malformed('path contains a NUL byte');

  const abs = realpathBestEffort(path.resolve(root, target));
  const rel = path.relative(root, abs);
  if (rel.startsWith('..') || path.isAbsolute(rel)) {
    throw containment(`path escapes the project root: ${target}`, { root, path: target });
  }
  const relPosix = toPosix(rel);
  if (scope && scope.length > 0 && !inScope(relPosix, scope)) {
    throw containment(`path is outside the active scope: ${target}`, { scope, path: target });
  }
  return { abs, rel: relPosix };
}

export function inScope(relPosix, scope) {
  if (!scope || scope.length === 0) return true;
  if (relPosix === '') return false;
  return scope.some((s) => relPosix === s || relPosix.startsWith(`${s}/`));
}

function shouldDescend(relDir, scope) {
  if (!scope || scope.length === 0) return true;
  if (relDir === '') return true;
  return scope.some(
    (s) => relDir === s || relDir.startsWith(`${s}/`) || s.startsWith(`${relDir}/`)
  );
}

export function normalizeScope(root, scope) {
  if (scope === undefined || scope === null) return [];
  // A single path is accepted as well as a list: the plugin's `set_scope`
  // command passes one path verbatim.
  const entries = typeof scope === 'string' ? [scope] : scope;
  if (!Array.isArray(entries)) {
    throw malformed('scope must be a string or an array of strings');
  }
  const out = new Set();
  for (const entry of entries) {
    if (typeof entry !== 'string') throw malformed('scope entries must be strings');
    const trimmed = entry.trim();
    if (trimmed === '' || trimmed === '.' || trimmed === './') return []; // whole root
    const { rel } = resolveWithin(root, trimmed, null);
    if (rel === '') return []; // whole root
    out.add(rel);
  }
  return [...out].sort();
}

// ---------------------------------------------------------------------------
// Request schema (strict)
// ---------------------------------------------------------------------------

const OP_SCHEMAS = Object.freeze({
  ping: {},
  close: {},
  watch: {
    root: { type: 'string', required: true },
    scope: { type: 'scope' },
    controlFile: { type: 'string', required: true },
  },
  set_scope: { scope: { type: 'scope', required: true } },
  detect_project: {},
  discover_tests: { changed: { type: 'string[]', required: true } },
  build_plan: {
    changed: { type: 'string[]', required: true },
    mode: { type: 'enum', values: ['targeted', 'suite'], default: 'targeted' },
  },
  execute_plan: {
    plan: { type: 'object', required: true },
    timeoutMs: { type: 'int' },
    maxOutputBytes: { type: 'int' },
    stopOnFailure: { type: 'bool' },
  },
});

export const SUPPORTED_OPS = Object.freeze(Object.keys(OP_SCHEMAS).sort());

function validateEnvelope(request) {
  if (request === null || typeof request !== 'object' || Array.isArray(request)) {
    throw malformed('request must be a JSON object');
  }
  if (!Object.hasOwn(request, 'v')) throw malformed('request is missing required field "v"');
  if (typeof request.v !== 'number' || !Number.isInteger(request.v)) {
    throw malformed('"v" must be an integer');
  }
  if (request.v !== PROTOCOL_VERSION) {
    throw new RunnerError(ERR.VERSION, `unsupported protocol version ${request.v}`, {
      supported: [PROTOCOL_VERSION],
    });
  }
  if (typeof request.id !== 'string' || request.id.length === 0) {
    throw malformed('"id" must be a non-empty string');
  }
  if (request.id.length > 128) throw malformed('"id" must be at most 128 characters');
  if (typeof request.op !== 'string' || request.op.length === 0) {
    throw malformed('"op" must be a non-empty string');
  }
  if (!Object.hasOwn(OP_SCHEMAS, request.op)) {
    throw new RunnerError(ERR.UNKNOWN_OP, `unknown op "${request.op}"`, {
      supported: SUPPORTED_OPS,
    });
  }
  const schema = OP_SCHEMAS[request.op];
  const allowed = new Set(['v', 'id', 'op', ...Object.keys(schema)]);
  for (const key of Object.keys(request)) {
    if (!allowed.has(key)) {
      throw malformed(`unknown field "${key}" for op "${request.op}"`, {
        allowed: [...allowed].sort(),
      });
    }
  }
}

function coerceParams(request, schema) {
  const params = {};
  for (const [name, spec] of Object.entries(schema)) {
    const present = Object.hasOwn(request, name) && request[name] !== undefined;
    if (!present) {
      if (spec.required) throw malformed(`missing required field "${name}"`);
      if (spec.default !== undefined) params[name] = spec.default;
      continue;
    }
    const value = request[name];
    switch (spec.type) {
      case 'string':
        if (typeof value !== 'string' || value.length === 0) {
          throw malformed(`"${name}" must be a non-empty string`);
        }
        params[name] = value;
        break;
      case 'string[]':
        if (!Array.isArray(value) || value.some((v) => typeof v !== 'string' || v.length === 0)) {
          throw malformed(`"${name}" must be an array of non-empty strings`);
        }
        params[name] = value;
        break;
      case 'scope': {
        // Accepts a single path or a list of paths.
        const list = typeof value === 'string' ? [value] : value;
        if (!Array.isArray(list) || list.some((v) => typeof v !== 'string' || v.length === 0)) {
          throw malformed(`"${name}" must be a non-empty string or an array of non-empty strings`);
        }
        params[name] = list;
        break;
      }
      case 'int':
        if (typeof value !== 'number' || !Number.isInteger(value) || value < 0) {
          throw malformed(`"${name}" must be a non-negative integer`);
        }
        params[name] = value;
        break;
      case 'bool':
        if (typeof value !== 'boolean') throw malformed(`"${name}" must be a boolean`);
        params[name] = value;
        break;
      case 'object':
        if (value === null || typeof value !== 'object' || Array.isArray(value)) {
          throw malformed(`"${name}" must be a JSON object`);
        }
        params[name] = value;
        break;
      case 'enum':
        if (!spec.values.includes(value)) {
          throw malformed(`"${name}" must be one of ${spec.values.join(', ')}`);
        }
        params[name] = value;
        break;
      /* c8 ignore next 2 */
      default:
        throw new RunnerError(ERR.INTERNAL, `unhandled schema type ${spec.type}`);
    }
  }
  return params;
}

// ---------------------------------------------------------------------------
// Context
// ---------------------------------------------------------------------------

export function createContext(options = {}) {
  const root = canonicalizeRoot(options.root);
  return {
    root,
    scope: normalizeScope(root, options.scope),
    seenIds: new Set(),
    closed: false,
    scopeEpoch: 0,
    defaultTimeoutMs: clampTimeout(options.defaultTimeoutMs ?? DEFAULT_TIMEOUT_MS),
    maxOutputBytes: clampOutput(options.maxOutputBytes ?? DEFAULT_MAX_OUTPUT_BYTES),
    spawn: options.spawn ?? nodeSpawn,
    signal: options.signal,
  };
}

const clampTimeout = (ms) => Math.max(1, Math.min(MAX_TIMEOUT_MS, Math.floor(ms)));
const clampOutput = (n) => Math.max(1024, Math.min(MAX_OUTPUT_BYTES, Math.floor(n)));

// ---------------------------------------------------------------------------
// handleRequest
// ---------------------------------------------------------------------------

/**
 * Handle a single v1 request. Never throws: protocol and execution failures are
 * returned as structured error responses so they stay visible to the host.
 */
export async function handleRequest(request, context) {
  const echoId =
    request !== null && typeof request === 'object' && typeof request.id === 'string'
      ? request.id
      : null;
  let op = null;
  try {
    validateEnvelope(request);
    op = request.op;
    if (context.seenIds.has(request.id)) {
      throw new RunnerError(ERR.DUPLICATE_ID, `request id "${request.id}" was already used`, {
        id: request.id,
      });
    }
    context.seenIds.add(request.id);
    if (context.closed && request.op !== 'ping' && request.op !== 'close') {
      throw new RunnerError(ERR.CLOSED, 'runner is closed');
    }
    const params = coerceParams(request, OP_SCHEMAS[request.op]);
    const result = await dispatch(request.op, params, context);
    return { v: PROTOCOL_VERSION, id: request.id, ok: true, op: request.op, result };
  } catch (err) {
    return errorResponse(echoId, op, err);
  }
}

function errorResponse(id, op, err) {
  const error =
    err instanceof RunnerError
      ? { code: err.code, message: err.message, ...(err.detail ? { detail: err.detail } : {}) }
      : { code: ERR.INTERNAL, message: String(err?.message ?? err), detail: { stack: err?.stack } };
  return { v: PROTOCOL_VERSION, id, ok: false, op, error };
}

async function dispatch(op, params, context) {
  switch (op) {
    case 'ping':
      return { pong: true, protocol: PROTOCOL_VERSION, ops: SUPPORTED_OPS, root: context.root };

    case 'close':
      context.closed = true;
      return { closed: true };

    case 'watch': {
      // The root is fixed at launch; a re-assertion is allowed, a change is not.
      const requested = canonicalizeRoot(params.root);
      if (requested !== context.root) {
        throw new RunnerError(
          ERR.ROOT_IMMUTABLE,
          'project root is immutable and cannot be changed after launch',
          { root: context.root, requested }
        );
      }
      if (params.scope !== undefined) context.scope = normalizeScope(context.root, params.scope);
      return { root: context.root, scope: context.scope, controlFile: params.controlFile };
    }

    case 'set_scope': {
      const next = normalizeScope(context.root, params.scope);
      context.scope = next;
      context.scopeEpoch += 1;
      return { scope: next, epoch: context.scopeEpoch };
    }

    case 'detect_project':
      return detectProject(context.root);

    case 'discover_tests':
      return discoverTests(params.changed, context);

    case 'build_plan':
      return buildPlan(params.changed, context, { mode: params.mode ?? 'targeted' });

    case 'execute_plan':
      return executePlan(params.plan, context, {
        timeoutMs: params.timeoutMs,
        maxOutputBytes: params.maxOutputBytes,
        stopOnFailure: params.stopOnFailure ?? false,
      });

    /* c8 ignore next 2 */
    default:
      throw new RunnerError(ERR.UNKNOWN_OP, `unknown op "${op}"`);
  }
}

// ---------------------------------------------------------------------------
// Filesystem helpers
// ---------------------------------------------------------------------------

const existsFile = (abs) => {
  try {
    return fs.statSync(abs).isFile();
  } catch {
    return false;
  }
};

const existsDir = (abs) => {
  try {
    return fs.statSync(abs).isDirectory();
  } catch {
    return false;
  }
};

function readJson(abs) {
  try {
    return JSON.parse(fs.readFileSync(abs, 'utf8'));
  } catch {
    return null;
  }
}

function listFiles(absDir) {
  try {
    return fs
      .readdirSync(absDir, { withFileTypes: true })
      .filter((e) => e.isFile() || e.isSymbolicLink())
      .map((e) => e.name)
      .sort();
  } catch {
    return [];
  }
}

/** Walk up from `startRelDir` to the root looking for any of `names`. */
function findUp(root, startRelDir, names) {
  let rel = startRelDir;
  for (;;) {
    const absDir = rel === '' ? root : path.join(root, rel);
    for (const name of names) {
      if (existsFile(path.join(absDir, name)) || existsDir(path.join(absDir, name))) {
        return rel;
      }
    }
    if (rel === '') return null;
    const parent = path.posix.dirname(rel);
    rel = parent === '.' ? '' : parent;
  }
}

const joinRel = (relDir, name) => (relDir === '' ? name : `${relDir}/${name}`);
const relDirOf = (rel) => {
  const dir = path.posix.dirname(rel);
  return dir === '.' ? '' : dir;
};

// ---------------------------------------------------------------------------
// Project detection
// ---------------------------------------------------------------------------

export function detectProject(root) {
  return {
    root,
    toolchains: {
      javascript: existsFile(path.join(root, 'package.json')),
      ruby: existsFile(path.join(root, 'Gemfile')) || existsDir(path.join(root, 'spec')),
      go: existsFile(path.join(root, 'go.mod')),
      elixir: existsFile(path.join(root, 'mix.exs')),
      swift: existsFile(path.join(root, 'Package.swift')),
    },
  };
}

export function classifyLanguage(relPath) {
  const ext = path.posix.extname(relPath).toLowerCase();
  if (JS_EXTS.includes(ext)) return 'javascript';
  if (ext === '.rb') return 'ruby';
  if (ext === '.go') return 'go';
  if (ext === '.ex' || ext === '.exs') return 'elixir';
  if (ext === '.swift') return 'swift';
  return null;
}

// ---------------------------------------------------------------------------
// Test discovery
// ---------------------------------------------------------------------------

const ok = (value) => ({ status: 'ok', ...value });
const missing = (changed, reason, detail) => ({ status: 'missing', changed, reason, ...detail });
const ambiguous = (changed, reason, candidates) => ({
  status: 'ambiguous',
  changed,
  reason,
  candidates: [...candidates].sort(),
});

/** @returns {{targets: object[], missing: object[], ambiguous: object[], unsupported: object[]}} */
export function discoverTests(changed, context) {
  const targets = [];
  const missingOut = [];
  const ambiguousOut = [];
  const unsupported = [];

  const seen = new Set();
  for (const raw of changed) {
    const { rel } = resolveWithin(context.root, raw, context.scope);
    if (seen.has(rel)) continue;
    seen.add(rel);

    const language = classifyLanguage(rel);
    if (language === null) {
      unsupported.push({ changed: rel, reason: 'unsupported_language' });
      continue;
    }
    const result = DISCOVERERS[language](rel, context.root);
    if (result.status === 'ok') targets.push({ language, changed: rel, ...result, status: 'ok' });
    else if (result.status === 'ambiguous') ambiguousOut.push({ language, ...result });
    else missingOut.push({ language, ...result });
  }

  const byChanged = (a, b) => (a.changed < b.changed ? -1 : a.changed > b.changed ? 1 : 0);
  return {
    targets: targets.sort(byChanged),
    missing: missingOut.sort(byChanged),
    ambiguous: ambiguousOut.sort(byChanged),
    unsupported: unsupported.sort(byChanged),
  };
}

// --- JavaScript / TypeScript ----------------------------------------------

export function isJsTestFile(rel) {
  const base = path.posix.basename(rel);
  const ext = path.posix.extname(base);
  if (!JS_EXTS.includes(ext)) return false;
  const stem = base.slice(0, -ext.length);
  if (JS_TEST_INFIX.some((infix) => stem.endsWith(infix))) return true;
  return rel.split('/').includes('__tests__');
}

/** Only an explicitly configured Jest or Vitest is accepted. Never guessed. */
export function detectJsRunner(root, pkgRelDir) {
  const absDir = pkgRelDir === '' ? root : path.join(root, pkgRelDir);
  const pkg = readJson(path.join(absDir, 'package.json')) ?? {};
  const names = new Set(listFiles(absDir));

  const jestConfig = [...names].filter((n) => /^jest\.config\.(js|cjs|mjs|ts|mts|cts|json)$/.test(n));
  const vitestConfig = [...names].filter((n) =>
    /^vitest\.(config|workspace)\.(js|cjs|mjs|ts|mts|cts|json)$/.test(n)
  );
  const hasJest = jestConfig.length > 0 || Object.hasOwn(pkg, 'jest');
  const hasVitest = vitestConfig.length > 0 || Object.hasOwn(pkg, 'vitest');

  if (hasJest && hasVitest) {
    return {
      status: 'ambiguous',
      reason: 'multiple_configured_test_runners',
      candidates: ['jest', 'vitest'],
    };
  }
  if (!hasJest && !hasVitest) {
    return { status: 'missing', reason: 'no_configured_test_runner' };
  }
  return { status: 'ok', runner: hasJest ? 'jest' : 'vitest' };
}

/** Resolve `node_modules/.bin/<name>` by walking up from pkgRelDir to root. */
export function resolveLocalBin(root, pkgRelDir, name) {
  let rel = pkgRelDir;
  for (;;) {
    const absDir = rel === '' ? root : path.join(root, rel);
    const bin = path.join(absDir, 'node_modules', '.bin', name);
    if (existsFile(bin)) return bin;
    if (rel === '') return null;
    const parent = path.posix.dirname(rel);
    rel = parent === '.' ? '' : parent;
  }
}

export function detectPackageManager(root, pkgRelDir) {
  const absDir = pkgRelDir === '' ? root : path.join(root, pkgRelDir);
  const lockfiles = [
    ['pnpm-lock.yaml', 'pnpm'],
    ['yarn.lock', 'yarn'],
    ['package-lock.json', 'npm'],
    ['bun.lockb', 'bun'],
    ['bun.lock', 'bun'],
  ];
  const found = new Set();
  for (const [file, pm] of lockfiles) {
    if (existsFile(path.join(absDir, file))) found.add(pm);
  }
  if (found.size === 0) return { status: 'missing', reason: 'package_manager_undetermined' };
  if (found.size > 1) {
    return { status: 'ambiguous', reason: 'multiple_lockfiles', candidates: [...found] };
  }
  return { status: 'ok', packageManager: [...found][0] };
}

function discoverJs(rel, root) {
  const pkgRelDir = findUp(root, relDirOf(rel), ['package.json']);
  if (pkgRelDir === null) return missing(rel, 'no_package_json');

  const runner = detectJsRunner(root, pkgRelDir);
  if (runner.status === 'ambiguous') {
    return ambiguous(rel, runner.reason, runner.candidates);
  }
  if (runner.status === 'missing') return missing(rel, runner.reason, { packageDir: pkgRelDir });

  // Exact changed-test mapping. No globbing, no heuristics.
  let testFiles;
  if (isJsTestFile(rel)) {
    testFiles = [rel];
  } else {
    const dir = relDirOf(rel);
    const base = path.posix.basename(rel);
    const stem = base.slice(0, -path.posix.extname(base).length);
    const candidates = [];
    for (const ext of JS_EXTS) {
      for (const infix of JS_TEST_INFIX) {
        candidates.push(joinRel(dir, `${stem}${infix}${ext}`));
        candidates.push(joinRel(joinRel(dir, '__tests__'), `${stem}${infix}${ext}`));
      }
      candidates.push(joinRel(joinRel(dir, '__tests__'), `${stem}${ext}`));
    }
    const hits = [...new Set(candidates)].filter((c) => existsFile(path.join(root, c)));
    if (hits.length === 0) return missing(rel, 'no_matching_test_file', { packageDir: pkgRelDir });
    if (hits.length > 1) return ambiguous(rel, 'multiple_matching_test_files', hits);
    testFiles = hits;
  }

  const bin = resolveLocalBin(root, pkgRelDir, runner.runner);
  if (bin === null) {
    return missing(rel, 'runner_binary_not_installed', {
      packageDir: pkgRelDir,
      runner: runner.runner,
    });
  }

  return ok({
    projectDir: pkgRelDir,
    runner: runner.runner,
    bin,
    testFiles,
  });
}

function jsStep(root, projectDir, runner, bin, testFiles) {
  const relToPkg = (f) => (projectDir === '' ? f : path.posix.relative(projectDir, f));
  const args =
    runner === 'jest'
      ? ['--runTestsByPath', ...testFiles.map((f) => path.join(root, f))]
      : ['run', ...testFiles.map(relToPkg)];
  return { command: bin, args };
}

function jsSuiteStep(root, projectDir) {
  const absDir = projectDir === '' ? root : path.join(root, projectDir);
  const pkg = readJson(path.join(absDir, 'package.json')) ?? {};
  const scripts = pkg.scripts ?? {};
  if (typeof scripts.test !== 'string' || scripts.test.trim() === '') {
    return { status: 'missing', reason: 'no_test_script' };
  }
  const pm = detectPackageManager(root, projectDir);
  if (pm.status !== 'ok') return pm;
  return { status: 'ok', command: pm.packageManager, args: ['run', 'test'] };
}

// --- Ruby / RSpec ----------------------------------------------------------

function discoverRuby(rel, root) {
  const projectDir = findUp(root, relDirOf(rel), ['Gemfile', '.rspec', 'spec']);
  if (projectDir === null) return missing(rel, 'no_ruby_project');
  const absProject = projectDir === '' ? root : path.join(root, projectDir);
  if (!existsDir(path.join(absProject, 'spec'))) {
    return missing(rel, 'no_spec_directory', { projectDir });
  }

  const inner = projectDir === '' ? rel : path.posix.relative(projectDir, rel);
  let testFiles;
  if (inner.startsWith('spec/') && inner.endsWith('_spec.rb')) {
    testFiles = [rel];
  } else {
    const dir = relDirOf(inner);
    const base = path.posix.basename(inner, '.rb');
    const segments = dir === '' ? [] : dir.split('/');
    const candidateDirs = new Set();
    candidateDirs.add(path.posix.join('spec', dir)); // spec/<dir>
    if (segments.length > 0 && (segments[0] === 'lib' || segments[0] === 'app')) {
      candidateDirs.add(path.posix.join('spec', segments.slice(1).join('/'))); // strip lib/app
    }
    const candidates = [...candidateDirs].map((d) =>
      joinRel(projectDir, path.posix.join(d, `${base}_spec.rb`))
    );
    const hits = [...new Set(candidates)].filter((c) => existsFile(path.join(root, c)));
    if (hits.length === 0) return missing(rel, 'no_matching_spec_file', { projectDir });
    if (hits.length > 1) return ambiguous(rel, 'multiple_matching_spec_files', hits);
    testFiles = hits;
  }

  const usesBundler = existsFile(path.join(absProject, 'Gemfile'));
  return ok({ projectDir, runner: 'rspec', usesBundler, testFiles });
}

function rubyStep(root, projectDir, usesBundler, testFiles) {
  const relFiles = testFiles.map((f) =>
    projectDir === '' ? f : path.posix.relative(projectDir, f)
  );
  return usesBundler
    ? { command: 'bundle', args: ['exec', 'rspec', ...relFiles] }
    : { command: 'rspec', args: [...relFiles] };
}

// --- Go --------------------------------------------------------------------

function discoverGo(rel, root) {
  const moduleDir = findUp(root, relDirOf(rel), ['go.mod']);
  if (moduleDir === null) return missing(rel, 'no_go_module');
  const pkgDir = relDirOf(rel);
  const absPkg = pkgDir === '' ? root : path.join(root, pkgDir);
  const testFiles = listFiles(absPkg)
    .filter((n) => n.endsWith('_test.go'))
    .map((n) => joinRel(pkgDir, n));
  if (testFiles.length === 0) {
    return missing(rel, 'no_test_files_in_package', { projectDir: moduleDir, packageDir: pkgDir });
  }
  // Go is package-granular: the unit of execution is the whole package.
  const relPkg = moduleDir === '' ? pkgDir : path.posix.relative(moduleDir, pkgDir);
  return ok({
    projectDir: moduleDir,
    runner: 'go',
    packageDir: pkgDir,
    goPackage: relPkg === '' ? '.' : `./${relPkg}`,
    testFiles,
  });
}

const goStep = (goPackages) => ({ command: 'go', args: ['test', ...goPackages] });

// --- Elixir ----------------------------------------------------------------

function discoverElixir(rel, root) {
  const projectDir = findUp(root, relDirOf(rel), ['mix.exs']);
  if (projectDir === null) return missing(rel, 'no_mix_project');
  const inner = projectDir === '' ? rel : path.posix.relative(projectDir, rel);

  let testFiles;
  if (inner.startsWith('test/') && inner.endsWith('_test.exs')) {
    testFiles = [rel];
  } else {
    const dir = relDirOf(inner);
    const base = path.posix.basename(inner).replace(/\.exs?$/, '');
    const segments = dir === '' ? [] : dir.split('/');
    const candidateDirs = new Set([path.posix.join('test', dir)]);
    if (segments[0] === 'lib') candidateDirs.add(path.posix.join('test', segments.slice(1).join('/')));
    const candidates = [...candidateDirs].map((d) =>
      joinRel(projectDir, path.posix.join(d, `${base}_test.exs`))
    );
    const hits = [...new Set(candidates)].filter((c) => existsFile(path.join(root, c)));
    if (hits.length === 0) return missing(rel, 'no_matching_test_file', { projectDir });
    if (hits.length > 1) return ambiguous(rel, 'multiple_matching_test_files', hits);
    testFiles = hits;
  }
  return ok({ projectDir, runner: 'mix', testFiles });
}

function elixirStep(projectDir, testFiles) {
  const relFiles = testFiles.map((f) =>
    projectDir === '' ? f : path.posix.relative(projectDir, f)
  );
  return { command: 'mix', args: ['test', ...relFiles] };
}

// --- Swift -----------------------------------------------------------------

function discoverSwift(rel, root) {
  const projectDir = findUp(root, relDirOf(rel), ['Package.swift']);
  if (projectDir === null) return missing(rel, 'no_package_swift');
  const inner = projectDir === '' ? rel : path.posix.relative(projectDir, rel);
  const base = path.posix.basename(inner, '.swift');

  let testFiles;
  let filter;
  if (inner.startsWith('Tests/') && /Tests?$/.test(base)) {
    testFiles = [rel];
    filter = base;
  } else {
    const segments = inner.split('/');
    if (segments[0] !== 'Sources' || segments.length < 3) {
      return missing(rel, 'not_a_swift_package_source', { projectDir });
    }
    const moduleName = segments[1];
    const subPath = segments.slice(2, -1).join('/');
    const candidates = ['Tests', 'Test'].map((suffix) =>
      joinRel(
        projectDir,
        path.posix.join('Tests', `${moduleName}Tests`, subPath, `${base}${suffix}.swift`)
      )
    );
    const hits = [...new Set(candidates)].filter((c) => existsFile(path.join(root, c)));
    if (hits.length === 0) return missing(rel, 'no_matching_test_file', { projectDir });
    if (hits.length > 1) return ambiguous(rel, 'multiple_matching_test_files', hits);
    testFiles = hits;
    filter = path.posix.basename(hits[0], '.swift');
  }
  return ok({ projectDir, runner: 'swift', filter, testFiles });
}

const swiftStep = (filters) => ({
  command: 'swift',
  args: ['test', ...filters.flatMap((f) => ['--filter', f])],
});

const DISCOVERERS = Object.freeze({
  javascript: discoverJs,
  ruby: discoverRuby,
  go: discoverGo,
  elixir: discoverElixir,
  swift: discoverSwift,
});

// ---------------------------------------------------------------------------
// Plan building (coalescing)
// ---------------------------------------------------------------------------

const sortUnique = (values) => [...new Set(values)].sort();

/**
 * Build a deterministic execution plan. Targets are coalesced per
 * (language, projectDir, runner) so N changed files in one package produce one
 * command invocation.
 */
export function buildPlan(changed, context, { mode = 'targeted' } = {}) {
  const discovery = discoverTests(changed, context);
  const root = context.root;
  const groups = new Map();

  for (const target of discovery.targets) {
    const key = `${target.language}\u0000${target.projectDir}\u0000${target.runner}`;
    let group = groups.get(key);
    if (!group) {
      group = {
        language: target.language,
        projectDir: target.projectDir,
        runner: target.runner,
        bin: target.bin,
        usesBundler: target.usesBundler,
        testFiles: [],
        goPackages: [],
        filters: [],
        changed: [],
      };
      groups.set(key, group);
    }
    group.changed.push(target.changed);
    group.testFiles.push(...target.testFiles);
    if (target.goPackage) group.goPackages.push(target.goPackage);
    if (target.filter) group.filters.push(target.filter);
  }

  const steps = [];
  const planMissing = [...discovery.missing];
  const planAmbiguous = [...discovery.ambiguous];

  const ordered = [...groups.values()].sort((a, b) =>
    `${a.language}${a.projectDir}` < `${b.language}${b.projectDir}` ? -1 : 1
  );

  for (const group of ordered) {
    const testFiles = sortUnique(group.testFiles);
    const changedFiles = sortUnique(group.changed);
    let spec;

    if (mode === 'suite' && group.language === 'javascript') {
      const suite = jsSuiteStep(root, group.projectDir);
      if (suite.status !== 'ok') {
        const entry = { language: group.language, changed: changedFiles[0], reason: suite.reason };
        if (suite.status === 'ambiguous') planAmbiguous.push({ ...entry, candidates: suite.candidates });
        else planMissing.push(entry);
        continue;
      }
      spec = { command: suite.command, args: suite.args };
    } else {
      switch (group.language) {
        case 'javascript':
          spec = jsStep(root, group.projectDir, group.runner, group.bin, testFiles);
          break;
        case 'ruby':
          spec = rubyStep(root, group.projectDir, group.usesBundler, testFiles);
          break;
        case 'go':
          spec = goStep(sortUnique(group.goPackages));
          break;
        case 'elixir':
          spec = elixirStep(group.projectDir, testFiles);
          break;
        case 'swift':
          spec = swiftStep(sortUnique(group.filters));
          break;
        /* c8 ignore next 2 */
        default:
          continue;
      }
    }

    steps.push({
      id: `${group.language}:${group.projectDir || '.'}:${group.runner}`,
      language: group.language,
      cwd: group.projectDir,
      command: spec.command,
      args: spec.args,
      testFiles,
      changed: changedFiles,
    });
  }

  return {
    v: PROTOCOL_VERSION,
    root,
    mode,
    steps,
    missing: planMissing,
    ambiguous: planAmbiguous,
    unsupported: discovery.unsupported,
  };
}

// ---------------------------------------------------------------------------
// Command allowlist
// ---------------------------------------------------------------------------

/** Only allowlisted bare commands, or a project-local node_modules/.bin binary. */
export function assertAllowedCommand(command, root) {
  if (typeof command !== 'string' || command.length === 0) {
    throw malformed('step.command must be a non-empty string');
  }
  if (command.includes('\0')) throw malformed('step.command contains a NUL byte');

  if (path.isAbsolute(command)) {
    const parent = path.dirname(command);
    const grandparent = path.dirname(parent);
    const withinRoot = !path.relative(root, command).startsWith('..');
    if (
      !withinRoot ||
      path.basename(parent) !== '.bin' ||
      path.basename(grandparent) !== 'node_modules'
    ) {
      throw new RunnerError(
        ERR.COMMAND_NOT_ALLOWED,
        `absolute commands must be a project-local node_modules/.bin binary: ${command}`,
        { command, root }
      );
    }
    return command;
  }

  if (command.includes('/') || command.includes(path.sep)) {
    throw new RunnerError(
      ERR.COMMAND_NOT_ALLOWED,
      `relative command paths are not allowed: ${command}`,
      { command }
    );
  }
  if (!ALLOWED_COMMANDS.has(command)) {
    throw new RunnerError(ERR.COMMAND_NOT_ALLOWED, `command "${command}" is not allowlisted`, {
      command,
      allowed: [...ALLOWED_COMMANDS].sort(),
    });
  }
  return command;
}

const STEP_KEYS = new Set(['id', 'language', 'cwd', 'command', 'args', 'testFiles', 'changed', 'timeoutMs']);

function validateStep(step, index, root) {
  if (step === null || typeof step !== 'object' || Array.isArray(step)) {
    throw malformed(`plan.steps[${index}] must be an object`);
  }
  for (const key of Object.keys(step)) {
    if (!STEP_KEYS.has(key)) throw malformed(`plan.steps[${index}] has unknown field "${key}"`);
  }
  if (typeof step.id !== 'string' || step.id.length === 0) {
    throw malformed(`plan.steps[${index}].id must be a non-empty string`);
  }
  if (!Array.isArray(step.args) || step.args.some((a) => typeof a !== 'string')) {
    throw malformed(`plan.steps[${index}].args must be an array of strings`);
  }
  if (step.args.some((a) => a.includes('\0'))) {
    throw malformed(`plan.steps[${index}].args contains a NUL byte`);
  }
  if (step.timeoutMs !== undefined) {
    if (typeof step.timeoutMs !== 'number' || !Number.isInteger(step.timeoutMs) || step.timeoutMs <= 0) {
      throw malformed(`plan.steps[${index}].timeoutMs must be a positive integer`);
    }
  }
  assertAllowedCommand(step.command, root);
  // cwd is contained in the root but is deliberately not scope-restricted:
  // a package root may legitimately sit above the scoped subtree.
  const { abs } = resolveWithin(root, step.cwd === undefined || step.cwd === '' ? '.' : step.cwd, null);
  return abs;
}

// ---------------------------------------------------------------------------
// Diagnostics
// ---------------------------------------------------------------------------

const DIAG_PATTERNS = [
  // go / swift / tsc style:  path/to/file.go:12:3: message
  /(?:^|\s)(?<file>[^\s:()]+\.[A-Za-z]+):(?<line>\d+):(?<column>\d+):\s+(?<message>.+?)\s*$/,
  // jest / vitest stack frames:  at fn (/abs/file.ts:12:3)
  /\((?<file>[^()\s]+\.[A-Za-z]+):(?<line>\d+):(?<column>\d+)\)/,
  // rspec rerun hints:  rspec ./spec/a_spec.rb:12
  /^\s*rspec\s+(?<file>\S+\.rb):(?<line>\d+)\s*$/,
  // elixir:  test/a_test.exs:12
  /^\s*(?<file>\S+_test\.exs):(?<line>\d+)\s*$/,
];

export function parseDiagnostics(text, { root, cwd }) {
  if (typeof text !== 'string' || text.length === 0) return [];
  const out = [];
  const seen = new Set();
  for (const rawLine of text.split('\n')) {
    if (out.length >= MAX_DIAGNOSTICS) break;
    for (const pattern of DIAG_PATTERNS) {
      const match = pattern.exec(rawLine);
      if (!match?.groups) continue;
      const { file, line, column, message } = match.groups;
      let rel;
      try {
        rel = resolveWithin(root, path.resolve(cwd, file), null).rel;
      } catch {
        break; // outside the root: never surface a path we cannot vouch for
      }
      const key = `${rel}:${line}:${column ?? 0}`;
      if (seen.has(key)) break;
      seen.add(key);
      out.push({
        file: rel,
        line: Number(line),
        column: column === undefined ? null : Number(column),
        message: (message ?? rawLine).trim(),
      });
      break;
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// executePlan
// ---------------------------------------------------------------------------

function childEnv() {
  return {
    ...process.env,
    CI: '1',
    NO_COLOR: '1',
    FORCE_COLOR: '0',
    TERM: 'dumb',
  };
}

function captureStream(stream, limit, onChunk) {
  const chunks = [];
  let bytes = 0;
  let truncated = false;
  stream?.on('data', (chunk) => {
    const buf = Buffer.isBuffer(chunk) ? chunk : Buffer.from(String(chunk));
    if (bytes < limit) {
      const room = limit - bytes;
      if (buf.length <= room) {
        chunks.push(buf);
        bytes += buf.length;
      } else {
        chunks.push(buf.subarray(0, room));
        bytes = limit;
        truncated = true;
      }
    } else {
      truncated = true;
    }
    onChunk?.();
  });
  return {
    read: () => Buffer.concat(chunks).toString('utf8'),
    get truncated() {
      return truncated;
    },
    get bytes() {
      return bytes;
    },
  };
}

function runStep(step, { cwdAbs, timeoutMs, maxOutputBytes, spawnFn, signal, root }) {
  return new Promise((resolve) => {
    const startedAt = Date.now();
    const base = {
      id: step.id,
      language: step.language ?? null,
      command: step.command,
      args: step.args,
      cwd: toPosix(path.relative(root, cwdAbs)) || '.',
      testFiles: step.testFiles ?? [],
    };

    if (signal?.aborted) {
      resolve({
        ...base,
        ok: false,
        code: null,
        signal: null,
        timedOut: false,
        aborted: true,
        durationMs: 0,
        stdout: '',
        stderr: '',
        truncated: false,
        diagnostics: [],
        error: { code: ERR.ABORTED, message: 'execution aborted before start' },
      });
      return;
    }

    let child;
    try {
      child = spawnFn(step.command, step.args, {
        cwd: cwdAbs,
        shell: false, // never a shell: no interpolation, no injection
        stdio: ['ignore', 'pipe', 'pipe'],
        env: childEnv(),
        windowsHide: true,
      });
    } catch (err) {
      resolve({
        ...base,
        ok: false,
        code: null,
        signal: null,
        timedOut: false,
        aborted: false,
        durationMs: Date.now() - startedAt,
        stdout: '',
        stderr: '',
        truncated: false,
        diagnostics: [],
        error: { code: ERR.SPAWN, message: `failed to spawn ${step.command}: ${err.message}` },
      });
      return;
    }

    const stdout = captureStream(child.stdout, maxOutputBytes);
    const stderr = captureStream(child.stderr, maxOutputBytes);

    let timedOut = false;
    let aborted = false;
    let spawnError = null;
    let settled = false;
    let killTimer = null;

    const hardKill = () => {
      killTimer = setTimeout(() => {
        try {
          child.kill('SIGKILL');
        } catch {
          /* already gone */
        }
      }, KILL_GRACE_MS);
      killTimer.unref?.();
    };

    const timer = setTimeout(() => {
      timedOut = true;
      try {
        child.kill('SIGTERM');
      } catch {
        /* already gone */
      }
      hardKill();
    }, timeoutMs);
    timer.unref?.();

    const onAbort = () => {
      aborted = true;
      try {
        child.kill('SIGTERM');
      } catch {
        /* already gone */
      }
      hardKill();
    };
    signal?.addEventListener?.('abort', onAbort, { once: true });

    const finish = (code, sig) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (killTimer) clearTimeout(killTimer);
      signal?.removeEventListener?.('abort', onAbort);

      const outText = stdout.read();
      const errText = stderr.read();
      const combined = `${outText}\n${errText}`;
      let diagnostics = [];
      try {
        diagnostics = parseDiagnostics(combined, { root, cwd: cwdAbs });
      } catch {
        diagnostics = [];
      }

      let error = null;
      if (spawnError) {
        error = { code: ERR.SPAWN, message: `failed to spawn ${step.command}: ${spawnError}` };
      } else if (timedOut) {
        error = { code: ERR.TIMEOUT, message: `step "${step.id}" timed out after ${timeoutMs}ms` };
      } else if (aborted) {
        error = { code: ERR.ABORTED, message: `step "${step.id}" was aborted` };
      }

      resolve({
        ...base,
        ok: error === null && code === 0,
        code: code ?? null,
        signal: sig ?? null,
        timedOut,
        aborted,
        durationMs: Date.now() - startedAt,
        stdout: outText,
        stderr: errText,
        truncated: stdout.truncated || stderr.truncated,
        diagnostics,
        ...(error ? { error } : {}),
      });
    };

    child.on('error', (err) => {
      spawnError = err.message;
      finish(null, null);
    });
    child.on('close', (code, sig) => finish(code, sig));
  });
}

/**
 * Execute a plan produced by `buildPlan`. Uses `spawn` with `shell: false`,
 * bounded per-step timeouts and bounded captured output. Failures are returned
 * (never swallowed) with structured diagnostics where the output can be parsed.
 */
export async function executePlan(plan, context, options = {}) {
  if (plan === null || typeof plan !== 'object' || Array.isArray(plan)) {
    throw malformed('plan must be an object');
  }
  if (plan.v !== undefined && plan.v !== PROTOCOL_VERSION) {
    throw new RunnerError(ERR.VERSION, `unsupported plan version ${plan.v}`, {
      supported: [PROTOCOL_VERSION],
    });
  }
  if (!Array.isArray(plan.steps)) throw malformed('plan.steps must be an array');

  const root = context.root;
  const timeoutMs = clampTimeout(options.timeoutMs ?? context.defaultTimeoutMs ?? DEFAULT_TIMEOUT_MS);
  const maxOutputBytes = clampOutput(
    options.maxOutputBytes ?? context.maxOutputBytes ?? DEFAULT_MAX_OUTPUT_BYTES
  );
  const spawnFn = options.spawn ?? context.spawn ?? nodeSpawn;
  const signal = options.signal ?? context.signal;

  // Validate every step up-front so an illegal command never runs a prefix of the plan.
  const cwds = plan.steps.map((step, index) => validateStep(step, index, root));

  const results = [];
  for (const [index, step] of plan.steps.entries()) {
    const stepTimeout = clampTimeout(step.timeoutMs ?? timeoutMs);
    const result = await runStep(step, {
      cwdAbs: cwds[index],
      timeoutMs: stepTimeout,
      maxOutputBytes,
      spawnFn,
      signal,
      root,
    });
    results.push(result);
    if (options.stopOnFailure && !result.ok) break;
  }

  return {
    ok: results.length > 0 && results.every((r) => r.ok),
    ran: results.length,
    total: plan.steps.length,
    steps: results,
    missing: plan.missing ?? [],
    ambiguous: plan.ambiguous ?? [],
    unsupported: plan.unsupported ?? [],
  };
}

// ---------------------------------------------------------------------------
// Snapshots
// ---------------------------------------------------------------------------

export function snapshotTree(root, scope, options = {}) {
  const ignoredDirs = options.ignoredDirs ?? IGNORED_DIRS;
  const maxEntries = options.maxEntries ?? MAX_SNAPSHOT_ENTRIES;
  const files = new Map();
  const stack = [''];
  let truncated = false;

  while (stack.length > 0) {
    const relDir = stack.pop();
    let entries;
    try {
      entries = fs.readdirSync(relDir === '' ? root : path.join(root, relDir), {
        withFileTypes: true,
      });
    } catch {
      continue;
    }
    for (const entry of entries) {
      const rel = joinRel(relDir, entry.name);
      if (entry.isDirectory()) {
        if (ignoredDirs.has(entry.name)) continue;
        if (!shouldDescend(rel, scope)) continue;
        stack.push(rel);
        continue;
      }
      if (!entry.isFile() && !entry.isSymbolicLink()) continue;
      if (!inScope(rel, scope)) continue;
      if (files.size >= maxEntries) {
        truncated = true;
        continue;
      }
      let stat;
      try {
        stat = fs.statSync(path.join(root, rel));
      } catch {
        continue;
      }
      if (!stat.isFile()) continue;
      files.set(rel, `${stat.mtimeMs}:${stat.size}:${stat.ino}`);
    }
  }
  return { files, truncated };
}

export function diffSnapshots(previous, next) {
  const changes = [];
  for (const [rel, stamp] of next) {
    const before = previous.get(rel);
    if (before === undefined) changes.push({ type: 'added', path: rel });
    else if (before !== stamp) changes.push({ type: 'changed', path: rel });
  }
  for (const rel of previous.keys()) {
    if (!next.has(rel)) changes.push({ type: 'removed', path: rel });
  }
  changes.sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : a.type < b.type ? -1 : 1));
  return changes;
}

// ---------------------------------------------------------------------------
// Control file
// ---------------------------------------------------------------------------

function createControlReader(file) {
  return { file, offset: 0, partial: '', decoder: new StringDecoder('utf8') };
}

function readControlLines(state) {
  let stat;
  try {
    stat = fs.statSync(state.file);
  } catch {
    return [];
  }
  if (stat.size < state.offset) {
    // truncated / rotated: resync from the start
    state.offset = 0;
    state.partial = '';
    state.decoder = new StringDecoder('utf8');
  }
  if (stat.size === state.offset) return [];

  let fd;
  try {
    fd = fs.openSync(state.file, 'r');
  } catch {
    return [];
  }
  try {
    const length = stat.size - state.offset;
    const buffer = Buffer.allocUnsafe(length);
    const read = fs.readSync(fd, buffer, 0, length, state.offset);
    state.offset += read;
    state.partial += state.decoder.write(buffer.subarray(0, read));
  } catch {
    return [];
  } finally {
    fs.closeSync(fd);
  }

  const parts = state.partial.split('\n');
  state.partial = parts.pop() ?? '';
  return parts.map((line) => line.trim()).filter((line) => line.length > 0);
}

// ---------------------------------------------------------------------------
// Batch evaluation (discover -> plan -> execute for one debounced batch)
// ---------------------------------------------------------------------------

/** Concatenate step output, bounded so one noisy step cannot flood the channel. */
function joinStepOutput(steps, limit) {
  const parts = [];
  let used = 0;
  for (const step of steps) {
    const text = `$ ${step.command} ${step.args.join(' ')}\n${step.stdout}${step.stderr}`;
    if (used >= limit) {
      parts.push('[output truncated]');
      break;
    }
    const slice = text.slice(0, limit - used);
    used += slice.length;
    parts.push(slice);
  }
  return parts.join('\n');
}

const BATCH_STATUS = Object.freeze({
  PASSED: 'passed',
  FAILED: 'failed',
  ERROR: 'error',
  UNRESOLVED: 'unresolved',
  NO_TESTS: 'no_tests',
});

/**
 * Turn a snapshot diff into a test outcome.
 *
 * Deleted files are never used as discovery inputs. A batch that resolves to no
 * runnable step reports `no_tests` / `unresolved` rather than an empty pass.
 */
export async function evaluateBatch(changes, context, options = {}) {
  const maxOutputBytes = clampOutput(
    options.maxOutputBytes ?? context.maxOutputBytes ?? DEFAULT_MAX_OUTPUT_BYTES
  );
  const empty = { tests: [], output: '', diagnostics: [], ambiguous: [], missing: [], unsupported: [], steps: [] };

  const candidates = sortUnique(
    changes.filter((change) => change.type !== 'removed').map((change) => change.path)
  );
  if (candidates.length === 0) {
    // `statusReason`, not `reason`: the batch's own `reason` is the wake cause.
    return { ...empty, status: BATCH_STATUS.NO_TESTS, statusReason: 'only_deletions' };
  }

  let plan;
  try {
    plan = buildPlan(candidates, context, { mode: options.mode ?? 'targeted' });
  } catch (err) {
    const error =
      err instanceof RunnerError
        ? { code: err.code, message: err.message }
        : { code: ERR.INTERNAL, message: String(err?.message ?? err) };
    return { ...empty, status: BATCH_STATUS.ERROR, error, output: error.message };
  }

  const tests = sortUnique(plan.steps.flatMap((step) => step.testFiles ?? []));
  const unresolved = plan.ambiguous.length + plan.missing.length;

  if (plan.steps.length === 0) {
    return {
      ...empty,
      tests,
      status: unresolved > 0 ? BATCH_STATUS.UNRESOLVED : BATCH_STATUS.NO_TESTS,
      ambiguous: plan.ambiguous,
      missing: plan.missing,
      unsupported: plan.unsupported,
    };
  }

  let run;
  try {
    run = await executePlan(plan, context, {
      maxOutputBytes,
      timeoutMs: options.timeoutMs,
      signal: options.signal,
    });
  } catch (err) {
    const error =
      err instanceof RunnerError
        ? { code: err.code, message: err.message }
        : { code: ERR.INTERNAL, message: String(err?.message ?? err) };
    return {
      ...empty,
      tests,
      status: BATCH_STATUS.ERROR,
      error,
      output: error.message,
      ambiguous: plan.ambiguous,
      missing: plan.missing,
      unsupported: plan.unsupported,
    };
  }

  const stepErrored = run.steps.some((step) => step.error);
  const status = stepErrored
    ? BATCH_STATUS.ERROR
    : run.ok && unresolved === 0
      ? BATCH_STATUS.PASSED
      : BATCH_STATUS.FAILED;

  return {
    tests,
    status,
    output: joinStepOutput(run.steps, maxOutputBytes),
    diagnostics: run.steps.flatMap((step) => step.diagnostics).slice(0, MAX_DIAGNOSTICS),
    ambiguous: plan.ambiguous,
    missing: plan.missing,
    unsupported: plan.unsupported,
    steps: run.steps.map((step) => ({
      id: step.id,
      command: step.command,
      args: step.args,
      cwd: step.cwd,
      ok: step.ok,
      code: step.code,
      timedOut: step.timedOut,
      truncated: step.truncated,
      ...(step.error ? { error: step.error } : {}),
    })),
  };
}

// ---------------------------------------------------------------------------
// Watcher
// ---------------------------------------------------------------------------

/**
 * Start the filesystem watcher.
 *
 * fs events only *wake* the watcher; the authoritative change set always comes
 * from a recursive snapshot diff, so missed or coalesced OS events cannot
 * produce a wrong answer. A 5s periodic reconcile guarantees liveness even when
 * recursive watching is unavailable.
 */
export function startWatcher(options) {
  const {
    id = 'watch',
    out = process.stdout,
    debounceMs = DEFAULT_DEBOUNCE_MS,
    reconcileMs = RECONCILE_MS,
    fsWatch = fs.watch,
    signal,
    onClose,
    // When false the watcher reports file changes but runs no tests. Used by
    // tests that only assert coalescing.
    autoRun = true,
    maxOutputBytes,
    timeoutMs,
  } = options;

  const context =
    options.context ??
    createContext({
      root: options.root,
      scope: options.scope,
      signal,
    });

  const controlFile = path.isAbsolute(options.controlFile)
    ? path.resolve(options.controlFile)
    : resolveWithin(context.root, options.controlFile, null).abs;

  fs.mkdirSync(path.dirname(controlFile), { recursive: true });
  fs.closeSync(fs.openSync(controlFile, 'a')); // create if absent, never truncate

  const control = createControlReader(controlFile);
  const watchers = [];
  const state = {
    closed: false,
    running: false,
    pending: null,
    debounceTimer: null,
    interval: null,
    previous: null,
    snapshotEpoch: context.scopeEpoch,
    seq: 0,
  };

  const write = (obj) => {
    if (out.writableEnded || out.destroyed) return;
    out.write(`${JSON.stringify(obj)}\n`);
  };

  let resolveDone;
  const done = new Promise((resolve) => {
    resolveDone = resolve;
  });

  function close(reason = 'closed') {
    if (state.closed) return;
    state.closed = true;
    context.closed = true;
    if (state.debounceTimer) clearTimeout(state.debounceTimer);
    if (state.interval) clearInterval(state.interval);
    for (const watcher of watchers) {
      try {
        watcher.close();
      } catch {
        /* already closed */
      }
    }
    signal?.removeEventListener?.('abort', onAbort);
    write({ v: PROTOCOL_VERSION, id, event: 'closed', op: 'closed', reason });
    onClose?.(reason);
    resolveDone(reason);
  }

  /** Flatten any failure into the `event:"error"` line shape. */
  function errorEvent(err, extra = {}) {
    const base = errorResponse(id, 'batch', err);
    return {
      ...base,
      event: 'error',
      code: base.error.code,
      message: base.error.message,
      ...extra,
    };
  }

  function onAbort() {
    close('aborted');
  }
  signal?.addEventListener?.('abort', onAbort, { once: true });

  async function handleControlLine(line) {
    let message;
    try {
      message = JSON.parse(line);
    } catch (err) {
      write({
        v: PROTOCOL_VERSION,
        id: null,
        event: 'error',
        ok: false,
        op: 'control',
        code: ERR.MALFORMED,
        message: `invalid JSON on control channel: ${err.message}`,
        error: { code: ERR.MALFORMED, message: `invalid JSON on control channel: ${err.message}` },
      });
      return;
    }
    const response = await handleRequest(message, context);
    write({
      ...response,
      event: response.ok ? 'response' : 'error',
      // Failures are flattened so an `event:"error"` consumer never has to dig.
      ...(response.ok
        ? {}
        : { code: response.error.code, message: response.error.message }),
    });
    if (response.ok && response.op === 'close') close('close_requested');
  }

  async function tick(reason) {
    if (state.closed) return;
    if (state.running) {
      state.pending = state.pending ?? reason;
      return;
    }
    state.running = true;
    try {
      for (const line of readControlLines(control)) {
        await handleControlLine(line);
        if (state.closed) return;
      }
      if (state.closed) return;

      if (state.snapshotEpoch !== context.scopeEpoch) {
        // A scope change re-baselines: the new subtree must not report as "added".
        state.previous = null;
        state.snapshotEpoch = context.scopeEpoch;
      }

      const snapshot = snapshotTree(context.root, context.scope);
      const first = state.previous === null;
      const changes = first ? [] : diffSnapshots(state.previous, snapshot.files);
      state.previous = snapshot.files;

      if (changes.length > 0) {
        state.seq += 1;
        const batchId = `${id}:${state.seq}`;
        const event = {
          v: PROTOCOL_VERSION,
          id,
          event: 'batch',
          op: 'batch',
          batchId,
          seq: state.seq,
          reason,
          paths: changes.map((change) => change.path),
          changes,
          truncated: snapshot.truncated,
          tests: [],
          status: BATCH_STATUS.NO_TESTS,
          output: '',
          diagnostics: [],
        };
        if (autoRun) {
          try {
            Object.assign(
              event,
              await evaluateBatch(changes, context, { maxOutputBytes, timeoutMs, signal })
            );
          } catch (err) {
            write(errorEvent(err, { batchId, paths: event.paths }));
          }
        }
        if (state.closed) return;
        write(event);
      }
    } catch (err) {
      write(errorEvent(err, { reason }));
    } finally {
      state.running = false;
      const pending = state.pending;
      state.pending = null;
      if (pending && !state.closed) queueMicrotask(() => void tick(pending));
    }
  }

  // Debounce: bursts of fs events collapse into a single snapshot + batch.
  function schedule(reason) {
    if (state.closed || state.debounceTimer) return;
    state.debounceTimer = setTimeout(() => {
      state.debounceTimer = null;
      void tick(reason);
    }, debounceMs);
  }

  let recursive = true;
  try {
    watchers.push(
      fsWatch(context.root, { recursive: true, persistent: true }, () => schedule('event'))
    );
  } catch {
    recursive = false;
    try {
      watchers.push(fsWatch(context.root, { persistent: true }, () => schedule('event')));
    } catch {
      /* rely entirely on the periodic reconcile */
    }
  }
  try {
    watchers.push(fsWatch(controlFile, { persistent: true }, () => schedule('control')));
  } catch {
    /* rely on the periodic reconcile to pick up control messages */
  }

  state.interval = setInterval(() => void tick('reconcile'), reconcileMs);

  write({
    v: PROTOCOL_VERSION,
    id,
    event: 'ready',
    op: 'ready',
    root: context.root,
    scope: context.scope,
    controlFile,
    recursive,
    reconcileMs,
    debounceMs,
    autoRun,
    pid: process.pid,
  });

  // Establish the baseline snapshot immediately (emits nothing).
  const ready = tick('initial');

  return { context, controlFile, close, done, ready, tick, state, recursive };
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

export function parseBootstrap(line) {
  let message;
  try {
    message = JSON.parse(line);
  } catch (err) {
    throw malformed(`bootstrap message is not valid JSON: ${err.message}`);
  }
  validateEnvelope(message);
  if (message.op !== 'watch') {
    throw malformed(`bootstrap op must be "watch", got "${message.op}"`, { op: message.op });
  }
  const params = coerceParams(message, OP_SCHEMAS.watch);
  return { v: message.v, id: message.id, op: message.op, ...params };
}

async function readFirstLine(stream) {
  const decoder = new StringDecoder('utf8');
  let buffer = '';
  for await (const chunk of stream) {
    buffer += decoder.write(Buffer.isBuffer(chunk) ? chunk : Buffer.from(String(chunk)));
    const index = buffer.indexOf('\n');
    if (index !== -1) return buffer.slice(0, index);
  }
  buffer += decoder.end();
  const index = buffer.indexOf('\n');
  return index === -1 ? buffer : buffer.slice(0, index);
}

export async function main(argv, io = {}) {
  const stdin = io.stdin ?? process.stdin;
  const stdout = io.stdout ?? process.stdout;
  const stderr = io.stderr ?? process.stderr;

  if (argv[0] !== 'watch' || argv.length !== 1) {
    stderr.write('usage: node runner.mjs watch\n');
    return 2;
  }

  let bootstrap;
  try {
    bootstrap = parseBootstrap(await readFirstLine(stdin));
    // Only the first line is protocol; stdin must not hold the event loop open.
    stdin.pause?.();
    stdin.unref?.();
  } catch (err) {
    stdout.write(`${JSON.stringify(errorResponse(null, 'watch', err))}\n`);
    return 2;
  }

  let watcher;
  try {
    watcher = startWatcher({
      id: bootstrap.id,
      root: bootstrap.root,
      scope: bootstrap.scope,
      controlFile: bootstrap.controlFile,
      out: stdout,
    });
  } catch (err) {
    stdout.write(`${JSON.stringify(errorResponse(bootstrap.id, 'watch', err))}\n`);
    return 2;
  }

  // The bootstrap id is consumed so a replay of the same id is rejected.
  watcher.context.seenIds.add(bootstrap.id);

  const shutdown = () => watcher.close('signal');
  process.once('SIGINT', shutdown);
  process.once('SIGTERM', shutdown);

  await watcher.ready;
  await watcher.done;
  return 0;
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(process.argv[1]).href === import.meta.url;

/* c8 ignore start */
if (invokedDirectly) {
  main(process.argv.slice(2))
    .then((code) => {
      process.exitCode = code;
    })
    .catch((err) => {
      process.stderr.write(`fatal: ${err?.stack ?? err}\n`);
      process.exitCode = 1;
    });
}
/* c8 ignore stop */

/**
 * The machine-readable integration contract. The host can assert against this
 * instead of hard-coding strings.
 */
export const PROTOCOL = Object.freeze({
  version: PROTOCOL_VERSION,
  launch: ['node', 'runner.mjs', 'watch'],
  /** One newline-terminated JSON object on the child's stdin, then stdin is unused. */
  bootstrap: Object.freeze({
    v: 1,
    id: '<sessionId>',
    op: 'watch',
    root: '<abs project root, immutable>',
    scope: '<rel path | [rel paths] | omitted for whole root>',
    controlFile: '<abs path; parent dirs are created, file is created if absent>',
  }),
  /** The host appends (or rewrites) versioned JSON lines into `controlFile`. */
  control: Object.freeze({
    transport: 'ndjson-file',
    append: true,
    rewriteSupported: true,
    setScope: { v: 1, id: '<unique>', op: 'set_scope', scope: '<rel path | [rel paths]>' },
    close: { v: 1, id: '<unique>', op: 'close' },
    ops: SUPPORTED_OPS,
  }),
  /** NDJSON on stdout. Every line carries an `event` discriminator. */
  events: Object.freeze(['ready', 'batch', 'response', 'error', 'closed']),
  batchEvent: Object.freeze({
    v: 1,
    id: '<sessionId>',
    event: 'batch',
    batchId: '<sessionId>:<seq>',
    paths: ['<rel changed path>'],
    tests: ['<rel test file>'],
    status: Object.values(BATCH_STATUS),
    output: '<combined, bounded stdout+stderr>',
    diagnostics: [{ file: '<rel>', line: 0, column: 0, message: '' }],
  }),
  errorEvent: Object.freeze({
    v: 1,
    id: '<sessionId>',
    event: 'error',
    code: Object.values(ERR),
    message: '<human readable>',
  }),
  exitCodes: Object.freeze({ 0: 'normal close', 2: 'bad invocation or bad bootstrap' }),
  tmpdir: os.tmpdir(),
});
