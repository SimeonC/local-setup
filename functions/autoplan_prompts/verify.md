## Verify phase — AUDIT ONLY
- YOUR ROLE IS AUDIT-ONLY. Do NOT edit files, stage, commit, push, or open a PR. Do NOT run tests, linters, type checkers, build commands, or any verification command from the plan. Inspect statically (diffs + file reads + grep).
- The pipeline runs verify BEFORE commit, so all in-scope changes are uncommitted by design. Use `git diff HEAD` and `git status`. Do NOT use `git log`. Do NOT flag "uncommitted" / "not yet committed" as an issue.
- Subject of audit: EVERY uncommitted change. Walk the full `git diff HEAD` — nothing in the diff is exempt.
- Two failure modes to catch:
  1. **Missing scope work** — a Scope bullet is not implemented in the diff.
  2. **Out-of-scope work** — changes appear in the diff that are not justified by Scope (drive-by edits, unrelated refactors, expansions).
- Structural checks: scope completeness, no scope creep, test integrity (no `.only`/`.skip`/TODO in touched tests; every new public function has a test).
- Domain checks: wiring (added functions/endpoints actually called from entry points), error handling at the diff's boundaries.

## Review summary (final message)
- As your FINAL chat message (separate from the sentinel file), print a concise review the user can scan before commit:
  - **Requested scope** — one line per plan Scope bullet, marked done / partial / missing.
  - **What the diff did** — short bullets of actual `git diff HEAD` changes (file + one-phrase intent).
  - **Verdict** — restate ALL_GOOD / ISSUES_FOUND; if issues, a one-line headline each.
- Keep it tight — no full diffs or file dumps. Still AUDIT-ONLY: do not edit files or run commands to produce it. The sentinel file remains the authoritative verdict.

## Verdict contract (sentinel file)
- If ALL checks pass: write exactly `ALL_GOOD` to $VERIFY_LOG.
- If ANY check fails: write `ISSUES_FOUND` on line 1 of $VERIFY_LOG, followed by a numbered list. For each issue include: file path, line number, and tag it as **Missing**, **Out-of-scope**, or **Quality**.
