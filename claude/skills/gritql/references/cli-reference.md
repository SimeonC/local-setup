# Grit CLI Quick Reference

| Command | Purpose |
|---------|---------|
| `grit apply <pattern> --dry-run` | Preview changes without applying |
| `grit apply <pattern>` | Apply the pattern |
| `grit apply <pattern> --force` | Apply even with uncommitted changes |
| `grit apply <pattern> --language <lang>` | Specify target language |
| `grit apply <pattern> -m <N>` | Limit to N matches |
| `grit patterns test --filter=<name>` | Run tests for a pattern |
| `grit patterns test --update` | Update expected test outputs |
| `grit check` | Check for pattern violations |
| `grit check --fix` | Auto-fix violations |
| `grit list` | List available patterns |
| `grit init` | Install grit modules |
