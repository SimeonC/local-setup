# Claude Pipeline Verification Checklist

After scaffolding a new pipeline, verify:

- [ ] All `.sh` files are executable (`ls -l scripts/<name>/`) — sourced helpers don't need `+x` but it's harmless
- [ ] Sentinel words in the verify prompt match the grep strings in bash
- [ ] `[PR-tag]` in prepare pre-flight matches `[PR-tag]` in final `gh pr create` title
- [ ] `tmp/` is in `.gitignore`
- [ ] Resume works: checkout a test branch, run `migrate.sh` (or equivalent work stage) directly — branch-derived fallback must populate `BATCH_LABEL`/`PR_ID`
- [ ] `exec` chain is correct: each stage ends with `exec "$SCRIPT_DIR/<next>.sh"`; `start.sh` just execs `prepare.sh`
- [ ] Max-attempt guards are present in any retry loop and any loop-back counter
- [ ] If a background service helper exists: it is **sourced** (not exec'd) in every stage that needs it, the PID var is exported, and an `EXIT` trap kills it
