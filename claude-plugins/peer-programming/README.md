# Peer programming plugin (local-only)

This mod is authored at `~/.claude/dev-mods/4edef55f-ceee-4925-8001-a069491fb871/peer-programming`. The local repository marketplace at `~/.config/fish/claude-plugins` exposes that source through a relative catalog entry and symlink. `setup.sh` wires the link; it does not install or enable the plugin. The fish `peer` command invokes the Claude wrapper with this plugin's `--plugin-dir`, so ordinary Claude sessions stay unaffected.

Peer mode is a teacher/reviewer workflow: Claude guides the user through one small implementation step and reviews source changes the user makes; a background reviewer may author tests automatically. Deterministic filesystem snapshots own change detection, test selection, and test execution. The watcher uses filesystem events to wake snapshots plus a 5-second reconciliation interval; generated/vendor paths are excluded in `runner.mjs`. `/peer:scope` changes only the current session's watch root; relative paths resolve under the initial project root and escaping/outside paths are rejected.

The `Write`, `Edit`, and `NotebookEdit` hooks deny direct source modifications while allowing discovered test files; the reviewer is restricted to `Read`, `Write`, and `Edit`, with implementation-write and out-of-batch-path checks. Obvious shell-write checks are best effort. These are **plugin guardrails, not an OS-enforced prohibition or sandbox**: shell commands and external tools can write around them.

Supported test ecosystems are JavaScript/TypeScript, Ruby, Go, Elixir, and Swift. Test mappings/commands are deterministic; missing or ambiguous configuration is reported, not guessed. Commands are spawned with an allowlist, `shell: false`, bounded output/time, and structured error reporting. Reviewer-authored test changes are detected by the same watcher and rerun once; only source changes start a review agent. Review findings are attached as context to the next user-originated prompt while preserving its text; they do not interrupt or auto-submit a turn.

## Optional persistent marketplace activation (not performed)

If persistent activation is later wanted, add the local catalog and install the entry explicitly:

```sh
claude plugin marketplace add ~/.config/fish/claude-plugins
claude plugin install peer@local-claude-plugins
```

Installing changes activation from the session-only `peer` command to the scope selected in the install flow. Do not load the installed copy and this same source via `--plugin-dir` in the same session.

Protocol requests/events are versioned and correlated by IDs. Malformed messages, version mismatches, duplicate IDs, runner timeouts, and crashes are visible errors; none are treated as test passes.
