---
name: command-output
description: How to run project commands and handle their output — when to capture to a file vs. run inline, which package scripts to prefer, and how to invoke test runners. Use before running tests, linters, type checks, builds, or any command whose output you need to inspect.
---

# Command Output

## Capturing output

- Only save command output to a file when running tests, linters, or commands
  with known/potential failures. For simple commands (build, install, git,
  etc.) just run them directly.
- When saving output: `> ./tmp/<filename>.txt 2>&1`, then process/query the file —
  never pipe long output inline, and never re-run a command just to parse its
  output.
- Always place output in the `./tmp` folder as that is always git ignored.

## Choosing the command

- Prefer `*:ai` versions of package.json scripts when available (e.g.
  `npm run lint:ai` not `npm run lint`).
- Run tests via project runners (e.g. NX), not directly via tool CLIs — runners
  set up necessary env vars.
