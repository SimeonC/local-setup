export type PendingRun = {
  id: string
  batchId: string
  paths: string[]
  tests: string[]
  testCandidates: string[]
  status: 'running' | 'passed' | 'failed' | 'error' | 'unresolved' | 'no_tests' | 'ambiguous'
  output: string
}

export type Finding = {
  batchId: string
  text: string
}

export type PeerState = {
  projectRoot: string
  watchRoot: string
  sessionId: string
  agentRuns: Record<string, string>
  seenBatches: string[]
  completedBatches: string[]
  testWrittenBatches: string[]
  pendingFindings: Finding[]
  runs: Record<string, PendingRun>
  controlFile?: string
  lastRun?: PendingRun
  experiencePrompted: boolean
  experience?: string
  analogies?: string
}

declare module 'claude-code' {
  interface PluginState {
    peer: {
      session: PeerState
    }
  }
}
