---
name: split-plan
description: Split a large autoplan plan into smaller sub-plans with parent references. Use when a plan has too many phases (>5), the user mentions "split plan", or wants to break work into smaller autoplan-compatible chunks.
---

# Split Plan into Sub-Plans

You are breaking down a large plan into smaller, focused sub-plans for sequential `autoplan` execution.

## Task

1. Read the plan file at `the path provided by the user`
2. Identify natural groupings or milestones
   - Aim for 3-5 phases per sub-plan
   - Respect logical dependencies (phases that must run in order stay together)
3. Create sub-plan files in the same directory as the original
   - Name them `{parent-slug}-part-{n}.md` (e.g., `auth-refactor-part-1.md`)
   - Each sub-plan includes its own **Context** section explaining its role in the larger effort
   - Add a **Parent Plan** reference at the top pointing to the original plan path
4. Update the original (parent) plan:
   - Replace detailed phase descriptions with references to each sub-plan
   - Parent becomes an index/tracker with phases like "Run sub-plan 1: {title}"
   - Retain overall Context but delegate execution details
5. Output summary of created sub-plans and the updated parent structure
6. Open all created/modified plan files in the user's default editor using `open <file>` so they can review the results directly
7. Suggest the user run `/refine-plan` on each sub-plan for a final readiness check before autoplan execution
