## Deterministic checks are harness-owned
- Do NOT run lint, typecheck, build, or full test suites. Those run deterministically in the `verify_cmds` harness phase that follows. Running them here wastes a Claude turn on work the harness will redo.
- You MAY run a single test file you just wrote/changed to confirm red→green within your own change, but do NOT chase regressions outside the diff yourself — the harness phase will surface them.
