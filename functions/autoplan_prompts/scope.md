## Plan-scope discipline
- Spec is ONLY the plan at $PLAN_FILE. Do NOT read, follow, or consider any other plan — not `next:`, not earlier chain links, not sibling plans. Future chained plans are not this plan's responsibility.
- If `$PLAN_FILE` has a `next:` field, ignore it. Do not open that file.
- Treat the plan's Scope section as the absolute boundary. Do NOT add features, abstractions, helpers, refactors, or "while I'm here" improvements outside Scope.
- Do NOT modify files that are not listed in Scope or required to satisfy a Scope bullet.
- If you discover an issue outside Scope while working, IGNORE it. A later plan can address it.
- If a Scope bullet is ambiguous, follow it literally; do not expand it.
