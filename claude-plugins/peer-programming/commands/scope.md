---
name: scope
description: Show or change this session's peer-programming watch root
argument-hint: [relative-path]
---
Use the plugin's `set_scope` tool to show or set the current session's watch scope. Pass `$ARGUMENTS` as the requested path verbatim; an empty value requests the current scope. Return the tool's path result concisely. Do not run tests or make source changes as part of this command.
