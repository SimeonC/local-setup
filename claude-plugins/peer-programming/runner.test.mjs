/**
 * Tests for the peer-programming runner. Node built-ins only.
 *
 *     node --test runner.test.mjs
 *
 * Everything runs against throwaway trees under os.tmpdir(). Watcher tests
 * stub `fs.watch` so coalescing and reconciliation are asserted deterministically
 * rather than by sleeping and hoping.
 */

import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';
import { Readable } from 'node:stream';
import { after, describe, it } from 'node:test';

import {
  ERR,
  PROTOCOL,
  PROTOCOL_VERSION,
  SUPPORTED_OPS,
  assertAllowedCommand,
  buildPlan,
  classifyLanguage,
  createContext,
  detectPackageManager,
  detectProject,
  diffSnapshots,
  discoverTests,
  evaluateBatch,
  executePlan,
  handleRequest,
  inScope,
  isJsTestFile,
  main,
  normalizeScope,
  parseBootstrap,
  parseDiagnostics,
  resolveWithin,
  snapshotTree,
  startWatcher,
} from './runner.mjs';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const tempDirs = [];

after(() => {
  for (const dir of tempDirs) {
    try {
      fs.rmSync(dir, { recursive: true, force: true });
    } catch {
      /* best effort */
    }
  }
});

/** Build a temp tree. Keys ending in `/` are directories. `#!` files get +x. */
function makeTree(spec = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'pp-runner-'));
  tempDirs.push(dir);
  const root = fs.realpathSync.native(dir);
  for (const [rel, content] of Object.entries(spec)) {
    const abs = path.join(root, rel);
    if (rel.endsWith('/')) {
      fs.mkdirSync(abs, { recursive: true });
      continue;
    }
    fs.mkdirSync(path.dirname(abs), { recursive: true });
    fs.writeFileSync(abs, content);
    if (typeof content === 'string' && content.startsWith('#!')) fs.chmodSync(abs, 0o755);
  }
  return root;
}

const sh = (body) => `#!/bin/sh\n${body}\n`;
const nodeScript = (source) => sh(`exec ${process.execPath} -e ${JSON.stringify(source)}`);

const req = (op, fields = {}, id = `r${Math.random().toString(36).slice(2)}`) => ({
  v: PROTOCOL_VERSION,
  id,
  op,
  ...fields,
});

/** Collects NDJSON written by the watcher. */
class LineSink {
  constructor() {
    this.lines = [];
    this.partial = '';
    this.raw = '';
  }

  write(chunk) {
    const text = String(chunk);
    this.raw += text;
    this.partial += text;
    const parts = this.partial.split('\n');
    this.partial = parts.pop() ?? '';
    for (const part of parts) {
      if (part.trim() === '') continue;
      try {
        this.lines.push(JSON.parse(part));
      } catch {
        // stderr carries plain text (usage); keep it in `raw` only.
      }
    }
    return true;
  }

  get writableEnded() {
    return false;
  }

  get destroyed() {
    return false;
  }

  events(name) {
    return this.lines.filter((line) => line.event === name);
  }
}

/** An fs.watch stub: never fires unless a captured callback is invoked. */
function makeWatchStub() {
  const callbacks = [];
  const fsWatch = (_target, optionsOrCb, maybeCb) => {
    const cb = typeof optionsOrCb === 'function' ? optionsOrCb : maybeCb;
    callbacks.push(cb);
    return { close() {}, on() {} };
  };
  return {
    fsWatch,
    fireRoot(times = 1) {
      for (let i = 0; i < times; i += 1) callbacks[0]?.('change', 'x');
    },
    get count() {
      return callbacks.length;
    },
  };
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** Poll until `predicate()` is truthy or the budget expires. */
async function waitFor(predicate, { timeout = 4000, interval = 15 } = {}) {
  const deadline = Date.now() + timeout;
  for (;;) {
    const value = predicate();
    if (value) return value;
    if (Date.now() > deadline) return null;
    await sleep(interval);
  }
}

// A minimal JS project whose "jest" binary is a controllable shell script.
function jsFixture({ jestBody = 'exit 0', extra = {} } = {}) {
  return makeTree({
    'package.json': JSON.stringify({ name: 'fx', scripts: { test: 'jest' } }),
    'jest.config.js': 'module.exports = {};',
    'package-lock.json': '{}',
    'src/a.ts': 'export const a = 1;\n',
    'src/a.test.ts': 'test("a", () => {});\n',
    'src/b.ts': 'export const b = 2;\n',
    'src/b.test.ts': 'test("b", () => {});\n',
    'node_modules/.bin/jest': sh(jestBody),
    ...extra,
  });
}

// ---------------------------------------------------------------------------
// Protocol
// ---------------------------------------------------------------------------

describe('protocol envelope', () => {
  const root = makeTree({ 'a.txt': 'x' });
  const ctx = () => createContext({ root });

  it('rejects non-objects', async () => {
    for (const bad of [null, 42, 'hi', []]) {
      const response = await handleRequest(bad, ctx());
      assert.equal(response.ok, false);
      assert.equal(response.error.code, ERR.MALFORMED);
      assert.equal(response.v, PROTOCOL_VERSION);
    }
  });

  it('requires an integer v', async () => {
    assert.equal((await handleRequest({ id: 'a', op: 'ping' }, ctx())).error.code, ERR.MALFORMED);
    assert.equal(
      (await handleRequest({ v: '1', id: 'a', op: 'ping' }, ctx())).error.code,
      ERR.MALFORMED
    );
    assert.equal(
      (await handleRequest({ v: 1.5, id: 'a', op: 'ping' }, ctx())).error.code,
      ERR.MALFORMED
    );
  });

  it('reports a version mismatch distinctly', async () => {
    const response = await handleRequest({ v: 2, id: 'a', op: 'ping' }, ctx());
    assert.equal(response.ok, false);
    assert.equal(response.error.code, ERR.VERSION);
    assert.deepEqual(response.error.detail.supported, [PROTOCOL_VERSION]);
  });

  it('requires a non-empty, bounded id', async () => {
    assert.equal((await handleRequest(req('ping', {}, ''), ctx())).error.code, ERR.MALFORMED);
    assert.equal(
      (await handleRequest({ v: 1, id: 'x'.repeat(129), op: 'ping' }, ctx())).error.code,
      ERR.MALFORMED
    );
  });

  it('rejects unknown ops and unknown fields', async () => {
    const unknownOp = await handleRequest(req('launch_missiles'), ctx());
    assert.equal(unknownOp.error.code, ERR.UNKNOWN_OP);
    assert.deepEqual(unknownOp.error.detail.supported, SUPPORTED_OPS);

    const unknownField = await handleRequest(req('ping', { sneaky: true }), ctx());
    assert.equal(unknownField.error.code, ERR.MALFORMED);
  });

  it('rejects a replayed request id', async () => {
    const context = ctx();
    const first = await handleRequest(req('ping', {}, 'dup'), context);
    assert.equal(first.ok, true);
    const second = await handleRequest(req('ping', {}, 'dup'), context);
    assert.equal(second.ok, false);
    assert.equal(second.error.code, ERR.DUPLICATE_ID);
    assert.equal(second.id, 'dup');
  });

  it('echoes the id on failure so nothing is lost silently', async () => {
    const response = await handleRequest({ v: 1, id: 'keep-me', op: 'nope' }, ctx());
    assert.equal(response.id, 'keep-me');
    assert.equal(response.ok, false);
  });

  it('answers ping with the supported surface', async () => {
    const response = await handleRequest(req('ping'), ctx());
    assert.equal(response.ok, true);
    assert.equal(response.result.protocol, PROTOCOL_VERSION);
    assert.deepEqual(response.result.ops, SUPPORTED_OPS);
  });

  it('refuses work after close but still answers', async () => {
    const context = ctx();
    assert.equal((await handleRequest(req('close'), context)).ok, true);
    const after = await handleRequest(req('detect_project'), context);
    assert.equal(after.ok, false);
    assert.equal(after.error.code, ERR.CLOSED);
  });

  it('validates required params per op', async () => {
    assert.equal((await handleRequest(req('discover_tests'), ctx())).error.code, ERR.MALFORMED);
    assert.equal(
      (await handleRequest(req('discover_tests', { changed: 'a.ts' }), ctx())).error.code,
      ERR.MALFORMED
    );
    assert.equal(
      (await handleRequest(req('build_plan', { changed: [], mode: 'wild' }), ctx())).error.code,
      ERR.MALFORMED
    );
  });
});

describe('bootstrap parsing', () => {
  const root = makeTree({ 'src/a.ts': '1' });

  it('rejects malformed JSON', () => {
    assert.throws(() => parseBootstrap('{not json'), (err) => err.code === ERR.MALFORMED);
  });

  it('rejects a non-watch op', () => {
    assert.throws(
      () => parseBootstrap(JSON.stringify(req('ping'))),
      (err) => err.code === ERR.MALFORMED
    );
  });

  it('rejects a version mismatch', () => {
    assert.throws(
      () => parseBootstrap(JSON.stringify({ v: 9, id: 'a', op: 'watch', root, controlFile: '/c' })),
      (err) => err.code === ERR.VERSION
    );
  });

  it('requires root and controlFile', () => {
    assert.throws(
      () => parseBootstrap(JSON.stringify({ v: 1, id: 'a', op: 'watch', root })),
      (err) => err.code === ERR.MALFORMED
    );
  });

  it('accepts scope as a single string or an array', () => {
    const asString = parseBootstrap(
      JSON.stringify({ v: 1, id: 'a', op: 'watch', root, scope: 'src', controlFile: '/c' })
    );
    assert.deepEqual(asString.scope, ['src']);
    const asArray = parseBootstrap(
      JSON.stringify({ v: 1, id: 'b', op: 'watch', root, scope: ['src'], controlFile: '/c' })
    );
    assert.deepEqual(asArray.scope, ['src']);
    assert.equal(asString.controlFile, '/c');
    assert.equal(asString.id, 'a');
  });
});

// ---------------------------------------------------------------------------
// Containment
// ---------------------------------------------------------------------------

describe('path containment', () => {
  const outside = makeTree({ 'evil.ts': 'export const evil = 1;\n' });
  const root = makeTree({
    'src/a.ts': '1',
    'other/b.ts': '2',
  });
  fs.symlinkSync(outside, path.join(root, 'escape'));
  fs.symlinkSync(path.join(outside, 'evil.ts'), path.join(root, 'src', 'evil.ts'));

  it('accepts ordinary in-root paths', () => {
    const { rel } = resolveWithin(root, 'src/a.ts', null);
    assert.equal(rel, 'src/a.ts');
  });

  it('rejects traversal out of the root', () => {
    assert.throws(
      () => resolveWithin(root, '../../etc/passwd', null),
      (err) => err.code === ERR.CONTAINMENT
    );
  });

  it('rejects absolute paths outside the root', () => {
    assert.throws(
      () => resolveWithin(root, '/etc/passwd', null),
      (err) => err.code === ERR.CONTAINMENT
    );
  });

  it('rejects a symlinked directory that leaves the root', () => {
    assert.throws(
      () => resolveWithin(root, 'escape/evil.ts', null),
      (err) => err.code === ERR.CONTAINMENT
    );
  });

  it('rejects a symlinked file that leaves the root', () => {
    assert.throws(
      () => resolveWithin(root, 'src/evil.ts', null),
      (err) => err.code === ERR.CONTAINMENT
    );
  });

  it('rejects NUL bytes', () => {
    assert.throws(() => resolveWithin(root, 'src/a\0.ts', null), (err) => err.code === ERR.MALFORMED);
  });

  it('rejects empty paths', () => {
    assert.throws(() => resolveWithin(root, '', null), (err) => err.code === ERR.MALFORMED);
  });

  it('enforces the active scope on top of the root', () => {
    assert.equal(resolveWithin(root, 'src/a.ts', ['src']).rel, 'src/a.ts');
    assert.throws(
      () => resolveWithin(root, 'other/b.ts', ['src']),
      (err) => err.code === ERR.CONTAINMENT
    );
  });

  it('treats an empty scope as the whole root', () => {
    assert.equal(inScope('anything/at/all', []), true);
    assert.equal(inScope('src/a.ts', ['src']), true);
    assert.equal(inScope('srcfoo/a.ts', ['src']), false);
    assert.equal(inScope('other/b.ts', ['src']), false);
  });

  it('normalises and de-duplicates scope entries', () => {
    assert.deepEqual(normalizeScope(root, ['src', 'src', './src']), ['src']);
    assert.deepEqual(normalizeScope(root, 'src'), ['src']);
    assert.deepEqual(normalizeScope(root, ['.']), []);
    assert.deepEqual(normalizeScope(root, undefined), []);
    assert.throws(() => normalizeScope(root, [123]), (err) => err.code === ERR.MALFORMED);
    assert.throws(
      () => normalizeScope(root, ['../elsewhere']),
      (err) => err.code === ERR.CONTAINMENT
    );
  });

  it('keeps the root immutable across the session', async () => {
    const context = createContext({ root });
    const other = makeTree({ 'x.ts': '1' });
    const response = await handleRequest(
      req('watch', { root: other, controlFile: '/tmp/c' }),
      context
    );
    assert.equal(response.ok, false);
    assert.equal(response.error.code, ERR.ROOT_IMMUTABLE);
    assert.equal(context.root, root);
  });

  it('narrows scope through set_scope and reports the epoch', async () => {
    const context = createContext({ root });
    const response = await handleRequest(req('set_scope', { scope: 'src' }), context);
    assert.equal(response.ok, true);
    assert.deepEqual(response.result.scope, ['src']);
    assert.equal(response.result.epoch, 1);
    assert.deepEqual(context.scope, ['src']);

    const escape = await handleRequest(req('set_scope', { scope: '../nope' }), context);
    assert.equal(escape.ok, false);
    assert.equal(escape.error.code, ERR.CONTAINMENT);
  });

  it('refuses out-of-scope discovery inputs', async () => {
    const context = createContext({ root, scope: ['src'] });
    const response = await handleRequest(req('discover_tests', { changed: ['other/b.ts'] }), context);
    assert.equal(response.ok, false);
    assert.equal(response.error.code, ERR.CONTAINMENT);
  });
});

// ---------------------------------------------------------------------------
// Discovery
// ---------------------------------------------------------------------------

describe('language classification', () => {
  it('maps known extensions and nothing else', () => {
    assert.equal(classifyLanguage('src/a.ts'), 'javascript');
    assert.equal(classifyLanguage('src/a.mjs'), 'javascript');
    assert.equal(classifyLanguage('lib/a.rb'), 'ruby');
    assert.equal(classifyLanguage('pkg/a.go'), 'go');
    assert.equal(classifyLanguage('lib/a.ex'), 'elixir');
    assert.equal(classifyLanguage('Sources/M/A.swift'), 'swift');
    assert.equal(classifyLanguage('README.md'), null);
  });

  it('recognises JS test files exactly', () => {
    assert.equal(isJsTestFile('src/a.test.ts'), true);
    assert.equal(isJsTestFile('src/a.spec.tsx'), true);
    assert.equal(isJsTestFile('src/__tests__/a.ts'), true);
    assert.equal(isJsTestFile('src/a.ts'), false);
    assert.equal(isJsTestFile('src/atest.ts'), false);
    assert.equal(isJsTestFile('src/a.test.md'), false);
  });
});

describe('javascript discovery', () => {
  it('maps a source file to its one exact test file', () => {
    const root = jsFixture();
    const context = createContext({ root });
    const { targets, missing, ambiguous } = discoverTests(['src/a.ts'], context);
    assert.equal(missing.length, 0);
    assert.equal(ambiguous.length, 0);
    assert.equal(targets.length, 1);
    assert.equal(targets[0].runner, 'jest');
    assert.deepEqual(targets[0].testFiles, ['src/a.test.ts']);
    assert.equal(targets[0].bin, path.join(root, 'node_modules/.bin/jest'));
  });

  it('passes a changed test file straight through', () => {
    const root = jsFixture();
    const { targets } = discoverTests(['src/a.test.ts'], createContext({ root }));
    assert.deepEqual(targets[0].testFiles, ['src/a.test.ts']);
  });

  it('refuses to guess when jest and vitest are both configured', () => {
    const root = jsFixture({ extra: { 'vitest.config.ts': 'export default {};' } });
    const { ambiguous, targets } = discoverTests(['src/a.ts'], createContext({ root }));
    assert.equal(targets.length, 0);
    assert.equal(ambiguous.length, 1);
    assert.equal(ambiguous[0].reason, 'multiple_configured_test_runners');
    assert.deepEqual(ambiguous[0].candidates, ['jest', 'vitest']);
  });

  it('reports missing when no runner is configured', () => {
    const root = makeTree({
      'package.json': JSON.stringify({ name: 'fx', scripts: { test: 'jest' } }),
      'src/a.ts': '1',
      'src/a.test.ts': '1',
    });
    const { missing } = discoverTests(['src/a.ts'], createContext({ root }));
    assert.equal(missing[0].reason, 'no_configured_test_runner');
  });

  it('reports missing when no test file exists', () => {
    const root = jsFixture({ extra: { 'src/lonely.ts': '1' } });
    const { missing } = discoverTests(['src/lonely.ts'], createContext({ root }));
    assert.equal(missing[0].reason, 'no_matching_test_file');
  });

  it('reports ambiguous when several test files match', () => {
    const root = jsFixture({
      extra: { 'src/a.spec.ts': 'test("a", () => {});\n' },
    });
    const { ambiguous } = discoverTests(['src/a.ts'], createContext({ root }));
    assert.equal(ambiguous[0].reason, 'multiple_matching_test_files');
    assert.deepEqual(ambiguous[0].candidates, ['src/a.spec.ts', 'src/a.test.ts']);
  });

  it('reports missing when the runner binary is not installed', () => {
    const root = makeTree({
      'package.json': JSON.stringify({ name: 'fx', jest: {} }),
      'src/a.ts': '1',
      'src/a.test.ts': '1',
    });
    const { missing } = discoverTests(['src/a.ts'], createContext({ root }));
    assert.equal(missing[0].reason, 'runner_binary_not_installed');
  });

  it('reports missing when there is no package.json at all', () => {
    const root = makeTree({ 'src/a.ts': '1' });
    const { missing } = discoverTests(['src/a.ts'], createContext({ root }));
    assert.equal(missing[0].reason, 'no_package_json');
  });

  it('flags unsupported languages rather than guessing', () => {
    const root = makeTree({ 'README.md': '# hi' });
    const { unsupported, targets } = discoverTests(['README.md'], createContext({ root }));
    assert.equal(targets.length, 0);
    assert.equal(unsupported[0].reason, 'unsupported_language');
  });

  it('detects the package manager only from an unambiguous lockfile', () => {
    const npm = makeTree({ 'package.json': '{}', 'package-lock.json': '{}' });
    assert.equal(detectPackageManager(npm, '').packageManager, 'npm');

    const none = makeTree({ 'package.json': '{}' });
    assert.equal(detectPackageManager(none, '').reason, 'package_manager_undetermined');

    const both = makeTree({ 'package.json': '{}', 'package-lock.json': '{}', 'yarn.lock': '' });
    const result = detectPackageManager(both, '');
    assert.equal(result.status, 'ambiguous');
    assert.equal(result.reason, 'multiple_lockfiles');
  });
});

describe('ruby, go, elixir and swift discovery', () => {
  it('maps a ruby source file to its spec and uses bundler when present', () => {
    const root = makeTree({
      Gemfile: 'source "https://rubygems.org"\n',
      'lib/foo.rb': 'class Foo; end\n',
      'spec/foo_spec.rb': 'describe Foo do; end\n',
    });
    const context = createContext({ root });
    const { targets } = discoverTests(['lib/foo.rb'], context);
    assert.equal(targets[0].runner, 'rspec');
    assert.equal(targets[0].usesBundler, true);
    assert.deepEqual(targets[0].testFiles, ['spec/foo_spec.rb']);

    const plan = buildPlan(['lib/foo.rb'], context);
    assert.equal(plan.steps[0].command, 'bundle');
    assert.deepEqual(plan.steps[0].args, ['exec', 'rspec', 'spec/foo_spec.rb']);
  });

  it('reports missing when a ruby spec does not exist', () => {
    const root = makeTree({ Gemfile: '', 'spec/.keep': '', 'lib/foo.rb': '' });
    const { missing } = discoverTests(['lib/foo.rb'], createContext({ root }));
    assert.equal(missing[0].reason, 'no_matching_spec_file');
  });

  it('runs go tests at package granularity', () => {
    const root = makeTree({
      'go.mod': 'module example.com/m\n',
      'pkg/a.go': 'package pkg\n',
      'pkg/a_test.go': 'package pkg\n',
    });
    const context = createContext({ root });
    const { targets } = discoverTests(['pkg/a.go'], context);
    assert.equal(targets[0].goPackage, './pkg');
    const plan = buildPlan(['pkg/a.go'], context);
    assert.equal(plan.steps[0].command, 'go');
    assert.deepEqual(plan.steps[0].args, ['test', './pkg']);
  });

  it('reports missing when a go package has no test files', () => {
    const root = makeTree({ 'go.mod': 'module m\n', 'pkg/a.go': 'package pkg\n' });
    const { missing } = discoverTests(['pkg/a.go'], createContext({ root }));
    assert.equal(missing[0].reason, 'no_test_files_in_package');
  });

  it('maps an elixir module to its test and builds mix test', () => {
    const root = makeTree({
      'mix.exs': 'defmodule M.MixProject do end\n',
      'lib/foo.ex': 'defmodule Foo do end\n',
      'test/foo_test.exs': 'defmodule FooTest do end\n',
    });
    const context = createContext({ root });
    const plan = buildPlan(['lib/foo.ex'], context);
    assert.equal(plan.steps[0].command, 'mix');
    assert.deepEqual(plan.steps[0].args, ['test', 'test/foo_test.exs']);
  });

  it('uses swift test with a filter, but only with a Package.swift', () => {
    const root = makeTree({
      'Package.swift': '// swift-tools-version:5.9\n',
      'Sources/M/A.swift': 'struct A {}\n',
      'Tests/MTests/ATests.swift': 'final class ATests {}\n',
    });
    const context = createContext({ root });
    const plan = buildPlan(['Sources/M/A.swift'], context);
    assert.equal(plan.steps[0].command, 'swift');
    assert.deepEqual(plan.steps[0].args, ['test', '--filter', 'ATests']);

    const bare = makeTree({ 'Sources/M/A.swift': 'struct A {}\n' });
    const { missing } = discoverTests(['Sources/M/A.swift'], createContext({ root: bare }));
    assert.equal(missing[0].reason, 'no_package_swift');
  });

  it('detects available toolchains without running anything', () => {
    const root = makeTree({ 'go.mod': '', 'package.json': '{}' });
    const detected = detectProject(root);
    assert.equal(detected.toolchains.go, true);
    assert.equal(detected.toolchains.javascript, true);
    assert.equal(detected.toolchains.swift, false);
  });
});

describe('plan building', () => {
  it('coalesces several changed files in one package into one step', () => {
    const root = jsFixture();
    const context = createContext({ root });
    const plan = buildPlan(['src/a.ts', 'src/b.ts'], context);
    assert.equal(plan.steps.length, 1);
    assert.deepEqual(plan.steps[0].testFiles, ['src/a.test.ts', 'src/b.test.ts']);
    assert.deepEqual(plan.steps[0].changed, ['src/a.ts', 'src/b.ts']);
    assert.equal(plan.steps[0].args[0], '--runTestsByPath');
    assert.equal(plan.steps[0].args.length, 3);
  });

  it('is deterministic for the same inputs in any order', () => {
    const root = jsFixture();
    const context = createContext({ root });
    const forwards = buildPlan(['src/a.ts', 'src/b.ts'], context);
    const backwards = buildPlan(['src/b.ts', 'src/a.ts'], context);
    assert.deepEqual(forwards.steps, backwards.steps);
  });

  it('carries missing and ambiguous entries through to the plan', () => {
    const root = jsFixture({ extra: { 'src/lonely.ts': '1', 'notes.md': '#' } });
    const plan = buildPlan(['src/a.ts', 'src/lonely.ts', 'notes.md'], createContext({ root }));
    assert.equal(plan.steps.length, 1);
    assert.equal(plan.missing.length, 1);
    assert.equal(plan.unsupported.length, 1);
  });
});

// ---------------------------------------------------------------------------
// Command allowlist and execution
// ---------------------------------------------------------------------------

describe('command allowlist', () => {
  const root = makeTree({ 'node_modules/.bin/jest': sh('exit 0') });

  it('accepts allowlisted bare commands', () => {
    for (const command of ['npm', 'go', 'mix', 'swift', 'bundle', 'rspec']) {
      assert.equal(assertAllowedCommand(command, root), command);
    }
  });

  it('accepts a project-local node_modules/.bin binary', () => {
    const bin = path.join(root, 'node_modules/.bin/jest');
    assert.equal(assertAllowedCommand(bin, root), bin);
  });

  it('rejects arbitrary bare commands', () => {
    assert.throws(
      () => assertAllowedCommand('rm', root),
      (err) => err.code === ERR.COMMAND_NOT_ALLOWED
    );
  });

  it('rejects absolute commands outside the project', () => {
    assert.throws(
      () => assertAllowedCommand('/bin/sh', root),
      (err) => err.code === ERR.COMMAND_NOT_ALLOWED
    );
  });

  it('rejects absolute paths inside the project that are not node_modules/.bin', () => {
    assert.throws(
      () => assertAllowedCommand(path.join(root, 'evil.sh'), root),
      (err) => err.code === ERR.COMMAND_NOT_ALLOWED
    );
  });

  it('rejects relative command paths', () => {
    assert.throws(
      () => assertAllowedCommand('./evil.sh', root),
      (err) => err.code === ERR.COMMAND_NOT_ALLOWED
    );
  });
});

describe('executePlan', () => {
  const root = makeTree({
    'node_modules/.bin/ok': sh('echo "all good"\nexit 0'),
    'node_modules/.bin/fail': sh('echo "src/a.ts:3:5: expected 1 to equal 2"\nexit 1'),
    'node_modules/.bin/slow': sh('exec sleep 30'),
    'node_modules/.bin/noisy': nodeScript("process.stdout.write('x'.repeat(300000))"),
    'src/a.ts': '1',
  });
  const bin = (name) => path.join(root, 'node_modules/.bin', name);
  const step = (name, overrides = {}) => ({
    id: name,
    language: 'javascript',
    cwd: '',
    command: bin(name),
    args: [],
    testFiles: [],
    changed: [],
    ...overrides,
  });

  it('reports a clean run as ok', async () => {
    const result = await executePlan({ steps: [step('ok')] }, createContext({ root }));
    assert.equal(result.ok, true);
    assert.equal(result.ran, 1);
    assert.equal(result.steps[0].code, 0);
    assert.match(result.steps[0].stdout, /all good/);
    assert.equal(result.steps[0].error, undefined);
  });

  it('never reports a non-zero exit as a pass', async () => {
    const result = await executePlan({ steps: [step('fail')] }, createContext({ root }));
    assert.equal(result.ok, false);
    assert.equal(result.steps[0].ok, false);
    assert.equal(result.steps[0].code, 1);
    assert.deepEqual(result.steps[0].diagnostics, [
      { file: 'src/a.ts', line: 3, column: 5, message: 'expected 1 to equal 2' },
    ]);
  });

  it('never reports an empty plan as a pass', async () => {
    const result = await executePlan({ steps: [] }, createContext({ root }));
    assert.equal(result.ok, false);
    assert.equal(result.ran, 0);
  });

  it('bounds the runtime and surfaces the timeout', async () => {
    const started = Date.now();
    const result = await executePlan({ steps: [step('slow')] }, createContext({ root }), {
      timeoutMs: 250,
    });
    assert.ok(Date.now() - started < 10_000, 'timed-out step must not block');
    assert.equal(result.ok, false);
    assert.equal(result.steps[0].timedOut, true);
    assert.equal(result.steps[0].error.code, ERR.TIMEOUT);
  });

  it('bounds captured output', async () => {
    const result = await executePlan({ steps: [step('noisy')] }, createContext({ root }), {
      maxOutputBytes: 2048,
    });
    assert.equal(result.steps[0].truncated, true);
    assert.equal(result.steps[0].stdout.length, 2048);
  });

  it('surfaces a spawn failure instead of passing', async () => {
    const result = await executePlan({ steps: [step('does-not-exist')] }, createContext({ root }));
    assert.equal(result.ok, false);
    assert.equal(result.steps[0].error.code, ERR.SPAWN);
    assert.equal(result.steps[0].code, null);
  });

  it('validates every step before running any of them', async () => {
    await assert.rejects(
      executePlan({ steps: [step('ok'), { ...step('ok'), id: 'evil', command: 'rm' }] }, createContext({ root })),
      (err) => err.code === ERR.COMMAND_NOT_ALLOWED
    );
  });

  it('rejects unknown step fields and bad arg types', async () => {
    const context = createContext({ root });
    await assert.rejects(
      executePlan({ steps: [{ ...step('ok'), surprise: 1 }] }, context),
      (err) => err.code === ERR.MALFORMED
    );
    await assert.rejects(
      executePlan({ steps: [{ ...step('ok'), args: [1] }] }, context),
      (err) => err.code === ERR.MALFORMED
    );
    await assert.rejects(
      executePlan({ steps: [{ ...step('ok'), args: ['a\0b'] }] }, context),
      (err) => err.code === ERR.MALFORMED
    );
  });

  it('rejects a cwd outside the root', async () => {
    await assert.rejects(
      executePlan({ steps: [step('ok', { cwd: '../..' })] }, createContext({ root })),
      (err) => err.code === ERR.CONTAINMENT
    );
  });

  it('rejects a plan with a mismatched version', async () => {
    await assert.rejects(
      executePlan({ v: 99, steps: [] }, createContext({ root })),
      (err) => err.code === ERR.VERSION
    );
  });

  it('stops after the first failure when asked', async () => {
    const result = await executePlan(
      { steps: [step('fail', { id: 'first' }), step('ok', { id: 'second' })] },
      createContext({ root }),
      { stopOnFailure: true }
    );
    assert.equal(result.ran, 1);
    assert.equal(result.total, 2);
    assert.equal(result.ok, false);
  });

  it('honours an abort signal', async () => {
    const controller = new AbortController();
    controller.abort();
    const result = await executePlan({ steps: [step('slow')] }, createContext({ root }), {
      signal: controller.signal,
    });
    assert.equal(result.steps[0].aborted, true);
    assert.equal(result.steps[0].error.code, ERR.ABORTED);
  });

  it('runs through handleRequest end to end', async () => {
    const response = await handleRequest(
      req('execute_plan', { plan: { v: 1, steps: [step('ok')] } }),
      createContext({ root })
    );
    assert.equal(response.ok, true);
    assert.equal(response.result.ok, true);
  });

  it('turns an illegal command into an error response, not a throw', async () => {
    const response = await handleRequest(
      req('execute_plan', { plan: { steps: [{ ...step('ok'), command: 'curl' }] } }),
      createContext({ root })
    );
    assert.equal(response.ok, false);
    assert.equal(response.error.code, ERR.COMMAND_NOT_ALLOWED);
  });
});

// ---------------------------------------------------------------------------
// Diagnostics
// ---------------------------------------------------------------------------

describe('parseDiagnostics', () => {
  const root = makeTree({ 'src/a.ts': '1', 'spec/a_spec.rb': '1', 'test/a_test.exs': '1' });

  it('extracts file:line:col diagnostics', () => {
    const out = parseDiagnostics('pkg/a.go:12:3: undefined: Foo', { root, cwd: root });
    assert.deepEqual(out, [{ file: 'pkg/a.go', line: 12, column: 3, message: 'undefined: Foo' }]);
  });

  it('extracts jest / vitest stack frames', () => {
    const text = `    at Object.<anonymous> (${path.join(root, 'src/a.ts')}:7:11)`;
    const out = parseDiagnostics(text, { root, cwd: root });
    assert.equal(out.length, 1);
    assert.equal(out[0].file, 'src/a.ts');
    assert.equal(out[0].line, 7);
    assert.equal(out[0].column, 11);
  });

  it('extracts rspec rerun hints and elixir locations', () => {
    const rspec = parseDiagnostics('rspec ./spec/a_spec.rb:12', { root, cwd: root });
    assert.equal(rspec[0].file, 'spec/a_spec.rb');
    assert.equal(rspec[0].line, 12);
    assert.equal(rspec[0].column, null);

    const elixir = parseDiagnostics('  test/a_test.exs:5', { root, cwd: root });
    assert.equal(elixir[0].file, 'test/a_test.exs');
    assert.equal(elixir[0].line, 5);
  });

  it('drops locations outside the root', () => {
    // Parses cleanly as a diagnostic, but resolves outside the project.
    const out = parseDiagnostics('/etc/hosts.conf:1:1: nope', { root, cwd: root });
    assert.deepEqual(out, []);
  });

  it('de-duplicates repeated locations and tolerates junk', () => {
    const text = 'pkg/a.go:1:1: boom\npkg/a.go:1:1: boom\nnothing here at all';
    assert.equal(parseDiagnostics(text, { root, cwd: root }).length, 1);
    assert.deepEqual(parseDiagnostics('', { root, cwd: root }), []);
    assert.deepEqual(parseDiagnostics(undefined, { root, cwd: root }), []);
  });
});

// ---------------------------------------------------------------------------
// Snapshots
// ---------------------------------------------------------------------------

describe('snapshotTree / diffSnapshots', () => {
  it('skips ignored directories', () => {
    const root = makeTree({
      'src/a.ts': '1',
      'node_modules/pkg/index.js': '1',
      '.git/HEAD': 'ref',
      'dist/out.js': '1',
      'coverage/lcov.info': '1',
      'vendor/x.rb': '1',
      'tmp/scratch': '1',
      '.next/build': '1',
      '.build/x': '1',
    });
    const { files } = snapshotTree(root, []);
    assert.deepEqual([...files.keys()], ['src/a.ts']);
  });

  it('honours the active scope', () => {
    const root = makeTree({ 'src/a.ts': '1', 'other/b.ts': '1' });
    const { files } = snapshotTree(root, ['src']);
    assert.deepEqual([...files.keys()], ['src/a.ts']);
  });

  it('classifies additions, changes and removals', () => {
    const before = new Map([
      ['a', '1'],
      ['b', '1'],
    ]);
    const after = new Map([
      ['a', '2'],
      ['c', '1'],
    ]);
    assert.deepEqual(diffSnapshots(before, after), [
      { type: 'changed', path: 'a' },
      { type: 'removed', path: 'b' },
      { type: 'added', path: 'c' },
    ]);
  });

  it('reports truncation rather than silently dropping files', () => {
    const root = makeTree({ 'a.ts': '1', 'b.ts': '1', 'c.ts': '1' });
    const { truncated, files } = snapshotTree(root, [], { maxEntries: 2 });
    assert.equal(truncated, true);
    assert.equal(files.size, 2);
  });
});

// ---------------------------------------------------------------------------
// Batch evaluation
// ---------------------------------------------------------------------------

describe('evaluateBatch', () => {
  it('runs the mapped tests and reports passed', async () => {
    const root = jsFixture({ jestBody: 'echo "ran $@"\nexit 0' });
    const result = await evaluateBatch(
      [{ type: 'changed', path: 'src/a.ts' }],
      createContext({ root })
    );
    assert.equal(result.status, 'passed');
    assert.deepEqual(result.tests, ['src/a.test.ts']);
    assert.match(result.output, /ran /);
  });

  it('reports failed with diagnostics when the runner exits non-zero', async () => {
    const root = jsFixture({
      jestBody: 'echo "src/a.ts:3:5: expected 1 to equal 2"\nexit 1',
    });
    const result = await evaluateBatch(
      [{ type: 'changed', path: 'src/a.ts' }],
      createContext({ root })
    );
    assert.equal(result.status, 'failed');
    assert.equal(result.diagnostics[0].file, 'src/a.ts');
    assert.equal(result.diagnostics[0].line, 3);
  });

  it('reports unresolved instead of a pass when nothing maps', async () => {
    const root = jsFixture({ extra: { 'src/lonely.ts': '1' } });
    const result = await evaluateBatch(
      [{ type: 'changed', path: 'src/lonely.ts' }],
      createContext({ root })
    );
    assert.equal(result.status, 'unresolved');
    assert.equal(result.missing.length, 1);
    assert.deepEqual(result.tests, []);
  });

  it('reports no_tests for a deletion-only batch', async () => {
    const root = jsFixture();
    const result = await evaluateBatch(
      [{ type: 'removed', path: 'src/a.ts' }],
      createContext({ root })
    );
    assert.equal(result.status, 'no_tests');
    assert.equal(result.statusReason, 'only_deletions');
  });

  it('reports error, never a pass, when a step cannot start', async () => {
    const root = jsFixture();
    fs.rmSync(path.join(root, 'node_modules/.bin/jest'));
    fs.writeFileSync(path.join(root, 'node_modules/.bin/jest'), 'not executable');
    const result = await evaluateBatch(
      [{ type: 'changed', path: 'src/a.ts' }],
      createContext({ root })
    );
    assert.equal(result.status, 'error');
    assert.equal(result.steps[0].error.code, ERR.SPAWN);
  });

  it('surfaces containment failures as an error status', async () => {
    const root = jsFixture();
    const context = createContext({ root, scope: ['src'] });
    const result = await evaluateBatch([{ type: 'changed', path: '../escape.ts' }], context);
    assert.equal(result.status, 'error');
    assert.equal(result.error.code, ERR.CONTAINMENT);
  });
});

// ---------------------------------------------------------------------------
// Watcher
// ---------------------------------------------------------------------------

describe('watcher', () => {
  function start(root, overrides = {}) {
    const out = new LineSink();
    const stub = makeWatchStub();
    const controlFile =
      overrides.controlFile ?? path.join(root, '.pp-session', 'nested', 'control.ndjson');
    const watcher = startWatcher({
      id: 'session-1',
      root,
      out,
      controlFile,
      fsWatch: stub.fsWatch,
      debounceMs: 25,
      reconcileMs: 40,
      autoRun: false,
      ...overrides,
    });
    return { out, stub, watcher, controlFile };
  }

  it('creates the control file and its parent directories', async () => {
    const root = makeTree({ 'src/a.ts': '1' });
    const { watcher, controlFile, out } = start(root);
    await watcher.ready;
    assert.equal(fs.existsSync(controlFile), true);
    const ready = out.events('ready')[0];
    assert.equal(ready.id, 'session-1');
    assert.equal(ready.root, root);
    assert.equal(ready.controlFile, controlFile);
    await watcher.close();
  });

  it('emits no batch for the baseline snapshot', async () => {
    const root = makeTree({ 'src/a.ts': '1' });
    const { watcher, out } = start(root);
    await watcher.ready;
    assert.equal(out.events('batch').length, 0);
    await watcher.close();
  });

  it('coalesces a burst of notifications into a single batch', async () => {
    const root = makeTree({ 'src/a.ts': '1' });
    const { watcher, out, stub } = start(root, { reconcileMs: 60_000 });
    await watcher.ready;

    for (let i = 0; i < 5; i += 1) {
      fs.writeFileSync(path.join(root, `src/new-${i}.ts`), `export const n${i} = ${i};\n`);
    }
    stub.fireRoot(12); // one debounce window, many notifications

    const batches = await waitFor(() => (out.events('batch').length > 0 ? out.events('batch') : null));
    assert.ok(batches, 'expected a batch');
    await sleep(120); // give any second batch a chance to appear
    assert.equal(out.events('batch').length, 1, 'burst must collapse into one batch');

    const batch = out.events('batch')[0];
    assert.equal(batch.reason, 'event');
    assert.equal(batch.paths.length, 5);
    assert.deepEqual(
      batch.paths,
      ['src/new-0.ts', 'src/new-1.ts', 'src/new-2.ts', 'src/new-3.ts', 'src/new-4.ts']
    );
    assert.ok(batch.changes.every((change) => change.type === 'added'));
    await watcher.close();
  });

  it('reconciles on a timer when no notification ever arrives', async () => {
    const root = makeTree({ 'src/a.ts': '1' });
    const { watcher, out } = start(root, { reconcileMs: 40 });
    await watcher.ready;

    fs.writeFileSync(path.join(root, 'src/c.ts'), 'export const c = 1;\n');
    const batches = await waitFor(() => (out.events('batch').length > 0 ? out.events('batch') : null));
    assert.ok(batches, 'reconcile must find the change without any fs event');
    assert.equal(batches[0].reason, 'reconcile');
    assert.deepEqual(batches[0].paths, ['src/c.ts']);
    await watcher.close();
  });

  it('detects changes and removals, not just additions', async () => {
    const root = makeTree({ 'src/a.ts': '1', 'src/b.ts': '1' });
    const { watcher, out } = start(root, { reconcileMs: 40 });
    await watcher.ready;

    fs.writeFileSync(path.join(root, 'src/a.ts'), 'changed content\n');
    fs.rmSync(path.join(root, 'src/b.ts'));

    const batch = await waitFor(() => out.events('batch')[0] ?? null);
    assert.ok(batch);
    const byPath = Object.fromEntries(batch.changes.map((c) => [c.path, c.type]));
    assert.equal(byPath['src/a.ts'], 'changed');
    assert.equal(byPath['src/b.ts'], 'removed');
    await watcher.close();
  });

  it('applies set_scope written to the control file', async () => {
    const root = makeTree({ 'src/a.ts': '1', 'other/b.ts': '1' });
    const { watcher, out, controlFile } = start(root, { reconcileMs: 40 });
    await watcher.ready;

    fs.appendFileSync(
      controlFile,
      `${JSON.stringify({ v: 1, id: 'c1', op: 'set_scope', scope: 'src' })}\n`
    );

    const response = await waitFor(() => out.events('response').find((l) => l.id === 'c1') ?? null);
    assert.ok(response, 'expected a response to the control message');
    assert.equal(response.ok, true);
    assert.deepEqual(response.result.scope, ['src']);
    assert.deepEqual(watcher.context.scope, ['src']);

    // After the scope change, out-of-scope writes must not produce batches.
    out.lines.length = 0;
    fs.writeFileSync(path.join(root, 'other/c.ts'), '1');
    await sleep(160);
    assert.equal(out.events('batch').length, 0);
    await watcher.close();
  });

  it('re-baselines after a scope change so the new subtree is not all "added"', async () => {
    const root = makeTree({ 'src/a.ts': '1', 'src/b.ts': '1', 'other/c.ts': '1' });
    const { watcher, out, controlFile } = start(root, { reconcileMs: 40 });
    await watcher.ready;

    fs.appendFileSync(
      controlFile,
      `${JSON.stringify({ v: 1, id: 'c1', op: 'set_scope', scope: 'src' })}\n`
    );
    await waitFor(() => out.events('response').find((l) => l.id === 'c1') ?? null);
    await sleep(160);
    assert.equal(out.events('batch').length, 0, 'narrowing scope must not fabricate a batch');
    await watcher.close();
  });

  it('reports malformed control JSON as an error event', async () => {
    const root = makeTree({ 'src/a.ts': '1' });
    const { watcher, out, controlFile } = start(root, { reconcileMs: 40 });
    await watcher.ready;

    fs.appendFileSync(controlFile, '{ this is not json\n');
    const error = await waitFor(() => out.events('error')[0] ?? null);
    assert.ok(error);
    assert.equal(error.code, ERR.MALFORMED);
    await watcher.close();
  });

  it('reports a rejected control request as an error event', async () => {
    const root = makeTree({ 'src/a.ts': '1' });
    const { watcher, out, controlFile } = start(root, { reconcileMs: 40 });
    await watcher.ready;

    fs.appendFileSync(
      controlFile,
      `${JSON.stringify({ v: 2, id: 'c1', op: 'set_scope', scope: 'src' })}\n`
    );
    const error = await waitFor(() => out.events('error').find((l) => l.id === 'c1') ?? null);
    assert.ok(error);
    assert.equal(error.code, ERR.VERSION);
    await watcher.close();
  });

  it('survives a control file that is rewritten rather than appended', async () => {
    const root = makeTree({ 'src/a.ts': '1' });
    const { watcher, out, controlFile } = start(root, { reconcileMs: 40 });
    await watcher.ready;

    fs.appendFileSync(
      controlFile,
      `${JSON.stringify({ v: 1, id: 'c1', op: 'set_scope', scope: 'src' })}\n`
    );
    await waitFor(() => out.events('response').find((l) => l.id === 'c1') ?? null);

    // Whole-file rewrite: the reader must resync from offset 0.
    fs.writeFileSync(
      controlFile,
      `${JSON.stringify({ v: 1, id: 'c2', op: 'set_scope', scope: '.' })}\n`
    );
    const second = await waitFor(() => out.events('response').find((l) => l.id === 'c2') ?? null);
    assert.ok(second, 'a rewritten control file must still be read');
    assert.deepEqual(second.result.scope, []);
    await watcher.close();
  });

  it('closes on a control close message and emits a closed event', async () => {
    const root = makeTree({ 'src/a.ts': '1' });
    const { watcher, out, controlFile } = start(root, { reconcileMs: 40 });
    await watcher.ready;

    fs.appendFileSync(controlFile, `${JSON.stringify({ v: 1, id: 'c1', op: 'close' })}\n`);
    const reason = await watcher.done;
    assert.equal(reason, 'close_requested');
    assert.equal(out.events('closed')[0].reason, 'close_requested');
  });

  it('closes on an abort signal', async () => {
    const root = makeTree({ 'src/a.ts': '1' });
    const controller = new AbortController();
    const { watcher, out } = start(root, { signal: controller.signal });
    await watcher.ready;
    controller.abort();
    assert.equal(await watcher.done, 'aborted');
    assert.equal(out.events('closed')[0].reason, 'aborted');
  });

  it('emits a batch carrying the full test outcome when autoRun is on', async () => {
    const root = jsFixture({ jestBody: 'echo "ran"\nexit 0' });
    const { watcher, out } = start(root, { autoRun: true, reconcileMs: 40 });
    await watcher.ready;

    fs.writeFileSync(path.join(root, 'src/a.ts'), 'export const a = 99;\n');
    const batch = await waitFor(() => out.events('batch')[0] ?? null, { timeout: 8000 });
    assert.ok(batch, 'expected a batch event');
    assert.equal(batch.v, PROTOCOL_VERSION);
    assert.equal(batch.id, 'session-1');
    assert.equal(batch.batchId, 'session-1:1');
    assert.deepEqual(batch.paths, ['src/a.ts']);
    assert.deepEqual(batch.tests, ['src/a.test.ts']);
    assert.equal(batch.status, 'passed');
    assert.match(batch.output, /ran/);
    assert.deepEqual(batch.diagnostics, []);
    await watcher.close();
  });

  it('emits status failed with diagnostics when the tests fail', async () => {
    const root = jsFixture({ jestBody: 'echo "src/a.ts:9:2: boom"\nexit 1' });
    const { watcher, out } = start(root, { autoRun: true, reconcileMs: 40 });
    await watcher.ready;

    fs.writeFileSync(path.join(root, 'src/a.ts'), 'export const a = 99;\n');
    const batch = await waitFor(() => out.events('batch')[0] ?? null, { timeout: 8000 });
    assert.ok(batch);
    assert.equal(batch.status, 'failed');
    assert.equal(batch.diagnostics[0].file, 'src/a.ts');
    assert.equal(batch.diagnostics[0].line, 9);
    await watcher.close();
  });

  it('every emitted line carries a v and an event discriminator', async () => {
    const root = makeTree({ 'src/a.ts': '1' });
    const { watcher, out, controlFile } = start(root, { reconcileMs: 40 });
    await watcher.ready;
    fs.appendFileSync(
      controlFile,
      `${JSON.stringify({ v: 1, id: 'c1', op: 'set_scope', scope: 'src' })}\n`
    );
    await waitFor(() => out.events('response').find((l) => l.id === 'c1') ?? null);
    await watcher.close();
    assert.ok(out.lines.length > 0);
    for (const line of out.lines) {
      assert.equal(line.v, PROTOCOL_VERSION);
      assert.ok(PROTOCOL.events.includes(line.event), `unexpected event: ${line.event}`);
    }
  });
});

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

describe('CLI', () => {
  it('rejects a bad invocation with exit code 2', async () => {
    const out = new LineSink();
    const err = new LineSink();
    const code = await main(['serve'], {
      stdin: Readable.from([]),
      stdout: out,
      stderr: err,
    });
    assert.equal(code, 2);
    assert.match(err.raw, /usage: node runner\.mjs watch/);
  });

  it('rejects a malformed bootstrap line with a structured error', async () => {
    const out = new LineSink();
    const code = await main(['watch'], {
      stdin: Readable.from(['{ nope\n']),
      stdout: out,
      stderr: new LineSink(),
    });
    assert.equal(code, 2);
    assert.equal(out.lines[0].ok, false);
    assert.equal(out.lines[0].error.code, ERR.MALFORMED);
  });

  it('rejects a bootstrap whose root does not exist', async () => {
    const out = new LineSink();
    const line = JSON.stringify({
      v: 1,
      id: 's1',
      op: 'watch',
      root: path.join(os.tmpdir(), 'pp-runner-definitely-missing'),
      controlFile: path.join(os.tmpdir(), 'pp-runner-missing-control'),
    });
    const code = await main(['watch'], {
      stdin: Readable.from([`${line}\n`]),
      stdout: out,
      stderr: new LineSink(),
    });
    assert.equal(code, 2);
    assert.equal(out.lines[0].ok, false);
  });

  it('runs the documented stdin-bootstrap / control-file lifecycle', async () => {
    const root = makeTree({ 'src/a.ts': '1' });
    const controlFile = path.join(root, '.pp-session', 'deep', 'control.ndjson');
    const out = new LineSink();
    const bootstrap = JSON.stringify({
      v: PROTOCOL_VERSION,
      id: 'cli-session',
      op: 'watch',
      root,
      scope: 'src',
      controlFile,
    });

    const finished = main(['watch'], {
      stdin: Readable.from([`${bootstrap}\n`]),
      stdout: out,
      stderr: new LineSink(),
    });

    const ready = await waitFor(() => out.events('ready')[0] ?? null, { timeout: 8000 });
    assert.ok(ready, 'expected a ready event');
    assert.equal(ready.id, 'cli-session');
    assert.deepEqual(ready.scope, ['src']);
    assert.equal(fs.existsSync(controlFile), true);

    // stdin is already exhausted; the control file is the only channel left.
    fs.appendFileSync(
      controlFile,
      `${JSON.stringify({ v: 1, id: 'c-close', op: 'close' })}\n`
    );

    const code = await finished;
    assert.equal(code, 0);
    assert.equal(out.events('closed')[0].reason, 'close_requested');
  });

  it('publishes a machine-readable contract', () => {
    assert.equal(PROTOCOL.version, PROTOCOL_VERSION);
    assert.deepEqual(PROTOCOL.launch, ['node', 'runner.mjs', 'watch']);
    assert.equal(PROTOCOL.bootstrap.op, 'watch');
    assert.equal(PROTOCOL.control.setScope.op, 'set_scope');
    assert.equal(PROTOCOL.batchEvent.event, 'batch');
    assert.equal(PROTOCOL.errorEvent.event, 'error');
    for (const name of ['ready', 'batch', 'response', 'error', 'closed']) {
      assert.ok(PROTOCOL.events.includes(name));
    }
    for (const status of ['passed', 'failed', 'error', 'unresolved', 'no_tests']) {
      assert.ok(PROTOCOL.batchEvent.status.includes(status));
    }
  });
});
