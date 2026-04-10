---
name: refine-plan
description: Evaluate and refine an autoplan plan for automation readiness. Use when the user wants to check if a plan is ready for autoplan, mentions "refine plan", "plan readiness", or wants to improve plan detail before running autoplan.
---

# Refine Plan for Automation Readiness

You are evaluating a plan for automated implementation via `autoplan`. Be thorough and specific.

## Task

1. Open the plan file in the user's default editor using `open the path provided by the user` so they can follow along as changes are made
2. Read the plan file at `the path provided by the user`
2. For each phase, evaluate:
   - Is the scope clear and well-defined?
   - Are acceptance criteria testable and verifiable?
   - Is there enough technical detail to implement without asking clarifying questions?
   - Are dependencies on other phases explicit and documented?
   - Does it have a **Verification** section? Every phase must have one — even if it's explicitly "Cannot validate here" (e.g., for infrastructure or config changes). Missing verification = "Needs Work".
3. Output a markdown table: **Phase** | **Status** (Ready/Needs Work) | **Issues**
4. Work through each "Needs Work" issue one at a time:
   - Use the AskUserQuestion tool for each individual issue — present the specific problem and your proposed fix as options (e.g., "Apply fix", "Skip", with descriptions of what changes)
   - Apply if approved, adjust if feedback given, skip if rejected
   - Move to the next issue
5. After all issues addressed, re-evaluate the plan
6. Repeat until all phases show "Ready"

## Complexity Check

After the initial evaluation, if the plan has more than 5 phases or phases are individually large/complex, use AskUserQuestion to suggest splitting:
- "This plan has N phases and looks like it would benefit from splitting into sub-plans. Switch to /split-plan?"
- Options: "Yes, split first" / "No, continue refining"
If the user chooses to split, invoke the split-plan skill instead of continuing.

## Iteration

Work through improvements individually — never batch them. Present one issue, get a response, apply it, move on. On final successful evaluation, summarize what was improved.

