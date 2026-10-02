import type { Engine, Register } from 'claude-code'
import type { PeerState, PendingRun } from '../types'

const STATE = { plugin: 'peer', key: 'session' } as const
const SOURCE_EXTS = /\.(?:[cm]?[jt]sx?|rb|go|exs?|swift|svelte|vue|html?|css|scss|sass|less|py|pyi|java|kt|kts|scala|rs|php|cs|c|cc|cpp|h|hpp|m|mm|sh|fish|sql|md|json|ya?ml|toml)$/i
const WATCH_EXTS = /\.(?:[cm]?[jt]sx?|rb|go|exs?|swift)$/i
const RUNNER = 'runner.mjs'
const MAX_FINDINGS = 20

const TEACHER_CONTEXT = `Peer-programming mode is active. Do not implement or edit source files: guide the person through one small learnable step, offer concise hints, and review changes they make. Test files are the exception and are your responsibility: proactively write and update them yourself, TDD-style — prefer a failing test first that defines the next step and directs the person's implementation — and never ask the person to write tests. The watcher follows the files you touch automatically; you need not manage its scope by hand. Adapt explanations to their stated experience and preferred analogies. Explain review findings with evidence, cause, and one focused next step. Watcher findings are queued context, not an interrupt or a submitted prompt.`

const REVIEWER_PROMPT = `You are the peer-programming background reviewer and test author. The task prompt contains only this change batch's changed source files, deterministic test candidates, and deterministic test output. Read only those supplied files. Review source changes for correctness, regressions, and edge cases; explain each finding with file and line evidence, cause, and a focused next step that helps the learner understand the change. You may create or update only conventionally named test files listed as candidates in the batch. Never edit implementation/source files, never run shell commands, never choose test commands or paths, and never ask the user to write tests. Keep findings concise; say explicitly when there are no actionable findings.`

export const isTestFile = (path: string): boolean => {
  const normalized = path.replaceAll('\\', '/')
  const base = normalized.split('/').at(-1) ?? ''
  return /(^|\/)__tests__\//i.test(normalized)
    || /(^|\/)(?:test|tests|spec|specs)\//i.test(normalized)
    || /\.(?:test|spec)\.[cm]?[jt]sx?$/i.test(base)
    || /_spec\.rb$/i.test(base)
    || /_test\.go$/i.test(base)
    || /_test\.exs$/i.test(base)
    || /_test\.rb$/i.test(base)
    || (/\.swift$/i.test(base) && (/(?:Tests?|Specs?)\//i.test(normalized) || /Tests?\.swift$/i.test(base)))
    || (/\.exs?$/i.test(base) && /(^|\/)test\//i.test(normalized))
    || (/\.ipynb$/i.test(base) && /(^|\/)(?:test|tests|spec|specs)\//i.test(normalized))
}

const isImplementationFile = (path: string): boolean => SOURCE_EXTS.test(path) && !isTestFile(path)
const isWatchSource = (path: string): boolean => WATCH_EXTS.test(path) && !isTestFile(path)

const slash = (path: string): string => path.replaceAll('\\', '/')

const lexicalPath = (path: string, base: string): string | undefined => {
  const value = slash(path)
  if (!value || value.startsWith('//') || /^[A-Za-z]:/.test(value) || value.startsWith('~')) return undefined
  const absolute = value.startsWith('/') ? value : `${slash(base).replace(/\/$/, '')}/${value}`
  const parts: string[] = []
  for (const part of absolute.split('/')) {
    if (!part || part === '.') continue
    if (part === '..') {
      if (parts.length === 0) return undefined
      parts.pop()
    } else {
      parts.push(part)
    }
  }
  return `/${parts.join('/')}`
}

const inside = (path: string, root: string): boolean => path === root || path.startsWith(`${root.replace(/\/$/, '')}/`)

const resolveTarget = async ($: Dollar, path: string, base: string): Promise<string | undefined> => {
  const candidate = lexicalPath(path, base)
  if (!candidate || !inside(candidate, base)) return undefined
  const own = await $.fs.stat(candidate, { resolve: true }).catch(() => undefined)
  if (own?.realPath) return inside(own.realPath, base) ? own.realPath : undefined

  let ancestor = candidate
  const missing: string[] = []
  while (ancestor !== base && ancestor !== '/') {
    const cut = ancestor.lastIndexOf('/')
    missing.unshift(ancestor.slice(cut + 1))
    ancestor = cut <= 0 ? '/' : ancestor.slice(0, cut)
    const stat = await $.fs.stat(ancestor, { resolve: true }).catch(() => undefined)
    if (stat?.realPath) {
      if (!inside(stat.realPath, base)) return undefined
      const target = [stat.realPath.replace(/\/$/, ''), ...missing].filter(Boolean).join('/')
      return inside(target, base) ? target : undefined
    }
  }
  return undefined
}

type Dollar = Pick<Engine, 'state' | 'session' | 'fs' | 'process' | 'env' | 'plugin' | 'agent' | 'tool' | 'ui'>

type WatchStep = { ok?: boolean }

type WatchBatch = {
  v: number
  event?: string
  batchId?: string
  runId?: string
  paths?: string[]
  tests?: string[]
  files?: string[]
  testCandidates?: string[]
  status?: PendingRun['status']
  output?: string
  diagnostics?: unknown[]
  steps?: WatchStep[]
  ambiguous?: unknown[]
  missing?: unknown[]
  code?: string
  message?: string
}

// Toasts are plain text (no ANSI color), so status colour comes from a leading
// glyph: ✅ green for pass, ❌ red for fail, ⚠️ amber for trouble, ➖ for skips.
const STATUS_GLYPH: Record<PendingRun['status'], string> = {
  running: '⏳',
  passed: '✅',
  failed: '❌',
  error: '⚠️',
  unresolved: '⚠️',
  ambiguous: '⚠️',
  no_tests: '➖',
}

const count = (value: unknown): number => (Array.isArray(value) ? value.length : 0)
const plural = (n: number, noun: string): string => `${n} ${noun}${n === 1 ? '' : 's'}`

/** One-line, colour-coded toast summary with pass/fail counts for a batch. */
const summarizeBatch = (event: WatchBatch, run: PendingRun): string => {
  const glyph = STATUS_GLYPH[run.status] ?? '•'
  const checks = count(event.steps)
  const passedChecks = (event.steps ?? []).filter(step => step?.ok).length
  const failedChecks = checks - passedChecks
  const issues = count(event.diagnostics)
  const files = run.paths.length
  const unresolved = count(event.ambiguous) + count(event.missing)

  const detail = (() => {
    switch (run.status) {
      case 'passed':
        return [checks ? plural(checks, 'check') : '', run.tests.length ? plural(run.tests.length, 'test file') : '']
          .filter(Boolean)
          .join(', ')
      case 'failed':
        return [
          checks ? `${failedChecks}/${checks} checks failed` : 'tests failed',
          issues ? plural(issues, 'issue') : '',
        ]
          .filter(Boolean)
          .join(', ')
      case 'error':
        return (event.message ?? run.output ?? 'runner error').split('\n')[0].slice(0, 120)
      case 'unresolved':
        return `${plural(unresolved, 'test mapping')} to resolve`
      case 'no_tests':
        return `no tests mapped for ${plural(files, 'changed file')}`
      default:
        return ''
    }
  })()

  const headline = `${glyph} Peer tests ${run.status}`
  return detail ? `${headline} — ${detail} · ${run.batchId}` : `${headline} · ${run.batchId}`
}

const readState = async ($: Dollar): Promise<{ value: PeerState | undefined; version: number }> => $.state.get(STATE)

const changeState = async ($: Dollar, change: (state: PeerState) => PeerState): Promise<PeerState> => {
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const held = await readState($)
    if (!held.value) throw new Error('peer session state is not initialized')
    const next = change(held.value)
    const saved = await $.state.set(STATE, next, { ifVersion: held.version })
    if (saved.isSet) return next
  }
  throw new Error('peer session state changed repeatedly; retry the operation')
}

const hasSourceChange = (paths: string[]): boolean => paths.some(isWatchSource)

const candidateTests = (paths: string[]): string[] => {
  const candidates = new Set<string>()
  for (const raw of paths) {
    if (!isWatchSource(raw)) continue
    const file = slash(raw)
    const parts = file.split('/')
    const base = parts.pop() ?? ''
    const ext = base.match(/\.[^.]+$/)?.[0] ?? ''
    const stem = ext ? base.slice(0, -ext.length) : base
    const dir = parts.join('/')
    const join = (...segments: string[]) => segments.filter(Boolean).join('/')
    if (/\.[cm]?[jt]sx?$/i.test(ext)) {
      candidates.add(join(dir, `${stem}.test${ext}`))
      candidates.add(join(dir, `${stem}.spec${ext}`))
      candidates.add(join(dir, '__tests__', `${stem}.test${ext}`))
    } else if (ext === '.rb') {
      const prefix = parts[0] === 'app' || parts[0] === 'lib' ? parts.slice(1) : parts
      candidates.add(join('spec', ...prefix, `${stem}_spec.rb`))
    } else if (ext === '.go') {
      candidates.add(join(dir, `${stem}_test.go`))
    } else if (ext === '.ex' || ext === '.exs') {
      const prefix = parts[0] === 'lib' ? parts.slice(1) : parts
      candidates.add(join('test', ...prefix, `${stem}_test.exs`))
    } else if (ext === '.swift' && parts[0] === 'Sources' && parts.length >= 2) {
      candidates.add(join('Tests', `${parts[1]}Tests`, ...parts.slice(2), `${stem}Tests.swift`))
    }
  }
  return [...candidates].slice(0, 32)
}

const formatFindingPrompt = (batch: WatchBatch): string => {
  const paths = Array.isArray(batch.paths) ? batch.paths.filter(path => isWatchSource(path)) : []
  const tests = Array.isArray(batch.tests) ? batch.tests.filter(path => isTestFile(path)) : []
  const testCandidates = Array.isArray(batch.testCandidates) ? batch.testCandidates.filter(path => isTestFile(path)) : candidateTests(paths)
  const diagnostics = Array.isArray(batch.diagnostics) ? batch.diagnostics : []
  return [
    `Change batch: ${String(batch.batchId)}`,
    `Changed files (read only these source changes):\n${paths.map((path: string) => `- ${path}`).join('\n') || '- none'}`,
    `Deterministic test candidates:\n${testCandidates.map((path: string) => `- ${path}`).join('\n') || tests.map((path: string) => `- ${path}`).join('\n') || '- none / ambiguous configuration'}`,
    `Deterministic test status: ${String(batch.status ?? 'unknown')}`,
    `Test output:\n${String(batch.output ?? '(no output)')}`,
    `Structured diagnostics:\n${JSON.stringify(diagnostics)}`,
  ].join('\n\n')
}

const addFinding = async ($: Dollar, agentId: string, answer: string): Promise<void> => {
  const held = await readState($)
  if (!held.value) return
  const batchId = held.value.agentRuns[agentId]
  if (!batchId) return
  await changeState($, state => ({
    ...state,
    completedBatches: [...state.completedBatches, batchId].slice(-100),
    pendingFindings: [...state.pendingFindings, { batchId, text: answer }].slice(-MAX_FINDINGS),
    agentRuns: Object.fromEntries(Object.entries(state.agentRuns).filter(([id]) => id !== agentId)),
  }))
  $.ui.toast(`Peer review queued for batch ${batchId}; it will appear with your next prompt.`)
}

const processBatch = async ($: Dollar, event: WatchBatch): Promise<void> => {
  if (event.v !== 1) {
    $.ui.toast(`Peer watcher protocol error: unsupported message version ${String(event.v)}`)
    return
  }
  if (event.event === 'error') {
    $.ui.toast(`Peer runner error ${String(event.code ?? '')}: ${event.message ?? 'unknown runner error'}`)
    return
  }
  if (event.event === 'ready' || event.event === 'response' || event.event === 'closed') return
  if (event.event !== 'batch' || typeof event.batchId !== 'string') {
    $.ui.toast(`Peer watcher protocol error: ${event.message || 'unexpected event'}`)
    return
  }
  const held = await readState($)
  if (!held.value || held.value.seenBatches.includes(event.batchId)) return
  const paths = Array.isArray(event.files) ? event.files.filter((path: unknown): path is string => typeof path === 'string') : Array.isArray(event.paths) ? event.paths.filter((path: unknown): path is string => typeof path === 'string') : []
  const tests = Array.isArray(event.tests) ? event.tests.filter((path: unknown): path is string => typeof path === 'string') : []
  const testCandidates = Array.isArray(event.testCandidates) ? event.testCandidates.filter((path: unknown): path is string => typeof path === 'string' && isTestFile(path)) : candidateTests(paths)
  const lastRun: PendingRun = {
    id: event.runId ?? event.batchId,
    batchId: event.batchId,
    paths,
    tests,
    testCandidates,
    status: event.status ?? 'error',
    output: String(event.output ?? event.message ?? ''),
  }
  await changeState($, state => ({
    ...state,
    lastRun,
    runs: { ...state.runs, [event.batchId!]: lastRun },
    seenBatches: [...state.seenBatches, event.batchId!].slice(-100),
  }))
  $.ui.toast(summarizeBatch(event, lastRun))
  if (!hasSourceChange(paths)) return
  if (held.value.agentRuns[event.batchId]) return
  await changeState($, state => ({ ...state, agentRuns: { ...state.agentRuns, [event.batchId!]: 'starting' } }))

  const spawned = await $.agent.spawn({
    subagentType: 'peer:reviewer',
    description: `Review ${event.batchId}`,
    prompt: `${REVIEWER_PROMPT}\n\n${formatFindingPrompt({ ...event, paths, tests })}`,
  })
  if (spawned.deny || !spawned.agentId) {
    await changeState($, state => ({
      ...state,
      agentRuns: Object.fromEntries(Object.entries(state.agentRuns).filter(([id]) => id !== event.batchId)),
    }))
    $.ui.toast(`Peer reviewer failed to start: ${spawned.deny ?? 'no agent id returned'}`)
    return
  }
  await changeState($, state => ({
    ...state,
    agentRuns: { ...Object.fromEntries(Object.entries(state.agentRuns).filter(([id]) => id !== event.batchId)), [spawned.agentId!]: event.batchId! },
  }))
}

const parseLines = async ($: Dollar, text: string, buffer: string): Promise<string> => {
  let rest = buffer + text
  let newline = rest.indexOf('\n')
  while (newline >= 0) {
    const line = rest.slice(0, newline).trim()
    rest = rest.slice(newline + 1)
    if (line) {
      try {
        await processBatch($, JSON.parse(line))
      } catch (error) {
        $.ui.toast(`Peer watcher event failed: ${String(error)}`)
      }
    }
    newline = rest.indexOf('\n')
  }
  return rest
}

const startWatcher = async ($: Dollar, root: string, scope: string, sessionId: string): Promise<void> => {
  const safeSession = sessionId.replace(/[^A-Za-z0-9_-]/g, '') || 'session'
  const tmp = (await $.env.get('TMPDIR'))?.replace(/\/$/, '') || '/tmp'
  const controlFile = `${tmp}/peer-programming-${safeSession}.control.json`
  await $.fs.write(controlFile, '')
  await changeState($, state => ({ ...state, controlFile }))
  void (async () => {
    let buffer = ''
    try {
      const watcher = $.process.spawn({
        argv: ['node', `${$.plugin.root}/${RUNNER}`, 'watch'],
        cwd: root,
        input: JSON.stringify({ v: 1, id: `watch-${safeSession}`, op: 'watch', root, scope, controlFile }),
      })
      for await (const piece of watcher) {
        if (piece.stream === 'stderr') {
          $.ui.toast(`Peer watcher: ${piece.text.trim().slice(0, 240)}`)
        } else {
          buffer = await parseLines($, piece.text, buffer)
        }
      }
      if (buffer.trim()) $.ui.toast(`Peer watcher ended with incomplete JSON: ${buffer.slice(0, 240)}`)
      const ended = await watcher.result
      if (ended.code !== 0 || ended.signal) {
        $.ui.toast(`Peer watcher stopped unexpectedly (code ${ended.code ?? 'signal'}${ended.signal ? `: ${ended.signal}` : ''}).`)
      }
    } catch (error) {
      $.ui.toast(`Peer watcher failed: ${String(error)}`)
    }
  })()
}

/**
 * Move the watcher to `dirAbs` (an existing directory already known to be inside
 * the project root). Writes a `set_scope` control message and records the new
 * watch root. A no-op when the scope is already there. Returns the applied root,
 * or undefined when there is no control channel yet.
 */
const applyWatchScope = async ($: Dollar, value: PeerState, dirAbs: string): Promise<string | undefined> => {
  if (!value.controlFile) return undefined
  if (value.watchRoot === dirAbs) return dirAbs
  const root = value.projectRoot.replace(/\/$/, '')
  const scope = dirAbs === value.projectRoot ? '.' : dirAbs.slice(root.length + 1)
  const current = await $.fs.read(value.controlFile).catch(() => '')
  const controlLog = typeof current === 'string' ? current : ''
  await $.fs.write(value.controlFile, `${controlLog}${JSON.stringify({ v: 1, id: `scope-${Date.now()}`, op: 'set_scope', scope })}\n`)
  await changeState($, state => ({ ...state, watchRoot: dirAbs }))
  return dirAbs
}

/** Follow foreground work: point the watcher at the directory of the edited file. */
const autoScopeToFile = async ($: Dollar, value: PeerState | undefined, fileAbs: string | undefined): Promise<void> => {
  if (!value || !fileAbs || !value.controlFile) return
  const cut = fileAbs.lastIndexOf('/')
  const dir = cut <= value.projectRoot.replace(/\/$/, '').length ? value.projectRoot : fileAbs.slice(0, cut)
  if (!inside(dir, value.projectRoot)) return
  await applyWatchScope($, value, dir).catch(() => undefined)
}

// The MCP result of a plugin tool must be a string, content blocks, or nothing —
// never a bare object — so the scope tool reports its outcome as text.
const runScopeTool = async ($: Dollar, path: string): Promise<string> => {
  const { value } = await readState($)
  if (!value) return 'Error: peer session state is not initialized.'
  if (!path.trim()) return `Watch scope: ${value.watchRoot}\nProject root: ${value.projectRoot}`
  const candidate = lexicalPath(path, value.projectRoot)
  if (!candidate || !inside(candidate, value.projectRoot)) return 'Error: watch scope must remain inside the project root.'
  const stat = await $.fs.stat(candidate, { resolve: true }).catch(() => undefined)
  if (!stat?.realPath || !inside(stat.realPath, value.projectRoot) || stat.kind !== 'dir') return 'Error: watch scope must resolve to an existing directory inside the project root.'
  if (!value.controlFile) return 'Error: watcher control channel is unavailable.'
  await applyWatchScope($, value, stat.realPath)
  return `Watch scope: ${stat.realPath}\nProject root: ${value.projectRoot}`
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const rootPath = await $.session.root()
    const rootStat = await $.fs.stat(rootPath, { resolve: true }).catch(() => undefined)
    if (!rootStat?.realPath) {
      $.ui.toast('Peer mode could not resolve the project root; watcher was not started.')
      return next(e)
    }
    const sessionId = await $.session.id()
    const held = await readState($)
    const scope = held.value?.watchRoot && inside(held.value.watchRoot, rootStat.realPath) ? held.value.watchRoot : rootStat.realPath
    const state: PeerState = {
      projectRoot: rootStat.realPath,
      watchRoot: scope,
      sessionId,
      agentRuns: held.value?.agentRuns ?? {},
      seenBatches: held.value?.seenBatches ?? [],
      completedBatches: held.value?.completedBatches ?? [],
      pendingFindings: held.value?.pendingFindings ?? [],
      runs: held.value?.runs ?? {},
      testWrittenBatches: held.value?.testWrittenBatches ?? [],
      experiencePrompted: held.value?.experiencePrompted ?? false,
      experience: held.value?.experience,
      analogies: held.value?.analogies,
      controlFile: held.value?.controlFile,
    }
    await $.state.set(STATE, state, { ifVersion: held.version })
    await $.tool.register({
      name: 'set_scope',
      description: 'Show or change this peer session’s watch directory. Relative paths resolve below the project root; escapes are rejected.',
      inputSchema: {
        type: 'object',
        properties: { path: { type: 'string', description: 'Empty to show the current scope; otherwise a relative path under the project root.' } },
        required: ['path'],
        additionalProperties: false,
      },
    })
    await $.agent.register({
      name: 'reviewer',
      description: 'Background peer reviewer and test author for a deterministic change batch.',
      prompt: REVIEWER_PROMPT,
      tools: ['Read', 'Write', 'Edit'],
      disallowedTools: ['Bash', 'NotebookEdit', 'Agent', 'Glob', 'Grep'],
      maxTurns: 8,
      background: true,
      permissionMode: 'acceptEdits',
      omitClaudeMd: true,
    })
    const started = await next(e)
    await startWatcher($, rootStat.realPath, scope, sessionId)
    return started
  })

  on('session.end', async ($, e, next) => {
    const { value } = await readState($)
    if (value?.controlFile) {
      const current = await $.fs.read(value.controlFile).catch(() => '')
      await $.fs.write(value.controlFile, `${typeof current === 'string' ? current : ''}${JSON.stringify({ v: 1, id: `close-${Date.now()}`, op: 'close' })}\n`).catch(() => undefined)
    }
    return next(e)
  })

  on('agent.offer', { agent: 'peer:reviewer' }, () => ({ isOffered: false }))

  on('tool.call', { tool: 'mcp__peer__set_scope' }, async ($, e) => {
    if (typeof e.path !== 'string') return { result: 'Error: path must be a string; pass an empty string to show the current scope.' }
    return { result: await runScopeTool($, e.path) }
  })

  on('tool.call', { tool: 'Read' }, async ($, e, next) => {
    if (typeof e.agentId !== 'string') return next(e)
    const { value } = await readState($)
    const batchId = value?.agentRuns[e.agentId]
    if (!value || !batchId || batchId === 'starting') return { deny: 'peer reviewer reads are limited to the files supplied for its assigned change batch' }
    const file = typeof e.file_path === 'string' ? e.file_path : ''
    if (!file) return { deny: 'peer reviewer must read only files supplied for its assigned change batch' }
    const target = await resolveTarget($, file, value.projectRoot)
    const batch = value.runs[batchId]
    const allowed = [...(batch?.paths ?? []), ...(batch?.tests ?? []), ...(batch?.testCandidates ?? [])]
      .map(path => lexicalPath(path, value.projectRoot))
      .filter((path): path is string => path !== undefined)
    if (!target || !allowed.some(path => path === target)) {
      return { deny: 'peer reviewer read is outside the current deterministic change batch' }
    }
    return next(e)
  })

  on('tool.call', { tool: 'Write' }, async ($, e, next) => {
    const { value } = await readState($)
    const file = typeof e.file_path === 'string' ? e.file_path : ''
    const target = file && value ? await resolveTarget($, file, value.projectRoot) : undefined
    if (target && isImplementationFile(target)) return { deny: 'peer mode does not let Claude implement source changes; make the small change yourself and I will review it. Test files may be authored automatically.' }
    if (file && SOURCE_EXTS.test(file) && !target) return { deny: 'peer mode could not canonicalize this source target, so the write was denied.' }
    if (typeof e.agentId === 'string') {
      const batchId = value?.agentRuns[e.agentId]
      const batch = batchId && value ? value.runs[batchId] : undefined
      const candidates = batch ? [...batch.testCandidates, ...batch.tests] : []
      const allowed = batch && target && candidates.some(path => lexicalPath(path, value.projectRoot) === target)
      if (!batch || batchId === 'starting' || !target || !isTestFile(target) || !allowed) return { deny: 'peer reviewer writes are limited to test candidates in its assigned deterministic change batch.' }
    } else if (target && WATCH_EXTS.test(target)) {
      await autoScopeToFile($, value, target)
    }
    return next(e)
  })

  on('tool.call', { tool: 'Edit' }, async ($, e, next) => {
    const { value } = await readState($)
    const file = typeof e.file_path === 'string' ? e.file_path : ''
    const target = file && value ? await resolveTarget($, file, value.projectRoot) : undefined
    if (target && isImplementationFile(target)) return { deny: 'peer mode does not let Claude implement source changes; make the small change yourself and I will review it. Test files may be authored automatically.' }
    if (file && SOURCE_EXTS.test(file) && !target) return { deny: 'peer mode could not canonicalize this source target, so the edit was denied.' }
    if (typeof e.agentId === 'string') {
      const batchId = value?.agentRuns[e.agentId]
      const batch = batchId && value ? value.runs[batchId] : undefined
      const candidates = batch ? [...batch.testCandidates, ...batch.tests] : []
      const allowed = batch && target && candidates.some(path => lexicalPath(path, value.projectRoot) === target)
      if (!batch || batchId === 'starting' || !target || !isTestFile(target) || !allowed) return { deny: 'peer reviewer writes are limited to test candidates in its assigned deterministic change batch.' }
    } else if (target && WATCH_EXTS.test(target)) {
      await autoScopeToFile($, value, target)
    }
    return next(e)
  })

  on('tool.call', { tool: 'NotebookEdit' }, async ($, e, next) => {
    const { value } = await readState($)
    const file = typeof e.notebook_path === 'string' ? e.notebook_path : ''
    const target = file && value ? await resolveTarget($, file, value.projectRoot) : undefined
    if (!file || !target) return { deny: 'peer mode could not canonicalize this notebook target, so the edit was denied.' }
    if (!isTestFile(target)) return { deny: 'peer mode does not let Claude edit implementation notebooks; make the change yourself and I will review it.' }
    if (typeof e.agentId === 'string') {
      const batchId = value?.agentRuns[e.agentId]
      const batch = batchId && value ? value.runs[batchId] : undefined
      const allowed = batch && [...batch.testCandidates, ...batch.tests].some(path => `${path}.ipynb` === target)
      if (!batch || !allowed) return { deny: 'peer reviewer notebook writes are limited to test candidates in its assigned change batch.' }
    }
    return next(e)
  })

  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const command = typeof e.command === 'string' ? e.command : ''
    const hasWriteSyntax = /(?:>>?|\btee\b|\bsed\s+-i\b|\bperl\s+-i\b|\b(?:apply_patch|git\s+apply)\b|\b(?:writeFile|writeFileSync|appendFile|appendFileSync)\b)/i.test(command)
    if (hasWriteSyntax) {
      const files = command.match(/[A-Za-z0-9_./-]+\.(?:[A-Za-z0-9]+)\b/gi) ?? []
      if (files.some(path => isImplementationFile(path) || (/\.ipynb$/i.test(path) && !isTestFile(path)))) {
        return { deny: 'peer mode blocks obvious shell-based implementation writes as a guardrail; this is not an OS sandbox. Use an approved test tool or make source changes yourself.' }
      }
    }
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    if (e.agentId) await addFinding($, e.agentId, e.answer)
    return next(e)
  })

  on('prompt.submit', async ($, e, next) => {
    const held = await readState($)
    if (!held.value) return next({ ...e, context: [...(e.context ?? []), TEACHER_CONTEXT] })
    const findings = held.value.pendingFindings
    const isHumanPrompt = e.origin.kind === 'composer' || e.origin.kind === 'bridge'
    const context = [...(e.context ?? []), TEACHER_CONTEXT]
    if (isHumanPrompt && findings.length) {
      context.push(`Queued peer review findings (from background batches; do not treat as a new user request):\n${findings.map(item => `Batch ${item.batchId}:\n${item.text}`).join('\n\n')}`)
      await changeState($, state => ({ ...state, pendingFindings: [], experiencePrompted: true }))
    } else if (isHumanPrompt && !held.value.experiencePrompted) {
      context.push('At the start of peer mode, adapt to the person’s stated experience and preferred analogies. If either is genuinely unclear, ask once in your first response; otherwise proceed without asking. Remember their answer and do not ask again. Never ask them to write tests.')
      await changeState($, state => ({ ...state, experiencePrompted: true }))
    }
    return next({ ...e, context })
  })
}
