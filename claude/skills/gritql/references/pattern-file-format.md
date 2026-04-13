# Grit Pattern File Format

Patterns live in `.grit/patterns/<pattern_name>.md`. The filename (minus `.md`) becomes the pattern name.

```markdown
---
level: info
tags: [refactor]
---
# Pattern Title

Brief description of what this pattern does.

\`\`\`grit
// GritQL body goes here
`old_code($var)` => `new_code($var)`
\`\`\`

## Test: description of positive case

\`\`\`typescript
// Input code
old_code("hello");
\`\`\`

\`\`\`typescript
// Expected output
new_code("hello");
\`\`\`

## Test: negative case (should not match)

\`\`\`typescript
// This code should be unchanged — single block with no expected output = negative test
unrelated_code("hello");
\`\`\`
```

## Test case rules

- **Single code block** = negative test (pattern should NOT match this code)
- **Two code blocks** = first is input, second is expected output (positive test)
- Run tests: `grit patterns test --filter=<pattern_name>`
