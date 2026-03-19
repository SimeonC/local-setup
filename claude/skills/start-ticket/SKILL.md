---
name: start-ticket
description: Start work on JIRA ticket(s) — retrieves ticket info, fast-forwards main, creates a branch, and gathers context.
---

Start work on JIRA ticket(s): $ARGUMENTS

- Tickets are always defined in JIRA.
- Use the available tools to retrieve the data. If the tools fail ask the user to provide details.
- Unless specified, new tickets should be on a new branch from main.

## Setup

1. Retrieve contents of all tickets to work on
2. Fast forward main branch
3. Checkout a new branch from main, the branch name should follow the format `<Ticket Key(s)>-<short-description>`. If more than one ticket key separate with a `-` like `MOPS-123-MOPS-345`. The short description should be a summary of all ticket changes, as unspecific as possible. If that's not possible omit the description.
4. Look for and ask for more details about what to fix and how to go about it.
