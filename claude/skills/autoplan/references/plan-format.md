# Plan File Format

## Frontmatter

```yaml
---
branch: feat/...           # required — git branch name
test_cmd: npm run test:ai   # required — command(s) to run tests; can chain manual_test
pr_title: "..."             # optional — PR title string; omit to skip PR creation (commits only)
prompts: ./<slug>-prompts.md # required — path to prompts file
next: ./<slug>-2.md         # optional — next plan in chain
---
```

### test_cmd: Automated and Manual Verification

`test_cmd` can contain automated test commands, `manual_test`, or both:

- **Automated only**: `test_cmd: npm run test:ai`
- **Chained**: `test_cmd: npm run test:ai && manual_test ./auth-refresh.manual.md`
- **Manual only**: `test_cmd: manual_test ./auth-refresh.manual.md`

All fields except `next` and `pr_title` are required. Paths in `prompts` and `next` are resolved relative to the plan file's directory.

## Body Sections

### Context
Why this work is needed. One or two sentences explaining the motivation or background.

### Scope
Concrete list of what to implement. Must name **specific files, functions, or interfaces** — not vague descriptions like "refactor X" or "improve Y".

Good:
- Add `UserAuthService.refreshToken(userId: string)` in `src/auth/user-auth.service.ts`
- Update `AuthController` to call `refreshToken` on 401 responses

Bad:
- Improve auth handling
- Refactor the service layer

### Verification
Specific, automatable checks — commands that pass or fail. Not subjective ("looks correct").

Good:
- `npm run test:ai -- --testPathPattern=auth`
- `npm run lint:ai`

Bad:
- Code looks correct
- Auth works as expected

### Out of Scope
Explicit list of known gaps NOT handled by this plan, each with reason or deferral pointer.
- <gap> — ignored because <reason>
- <gap> — deferred to ./<slug>-followup.md

## Example

```markdown
---
branch: feat/auth-refresh
test_cmd: npm run test:ai
pr_title: "Add token refresh to auth service"
prompts: ./auth-refresh-prompts.md
next: ./auth-refresh-2.md
---

# Add Token Refresh

## Context
Access tokens expire after 1 hour. Currently users are logged out; we need silent refresh.

## Scope
- Add `refreshToken(userId: string): Promise<string>` to `src/auth/user-auth.service.ts`
- Add `POST /auth/refresh` endpoint in `src/auth/auth.controller.ts`
- Add unit tests in `src/auth/user-auth.service.spec.ts`

## Verification
- `npm run test:ai -- --testPathPattern=user-auth.service`
- `npm run lint:ai`
```
