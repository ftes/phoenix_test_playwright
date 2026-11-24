---
name: usage-rules
description: "Use when looking up docs for Elixir, OTP or a dependency: `mix usage_rules.docs` and `mix usage_rules.search_docs`."
metadata:
  managed-by: usage-rules
---

<!-- usage-rules-skill-start -->
## Additional References

### usage_rules

- [usage_rules](references/usage_rules/usage_rules.md)

## Searching Documentation

```sh
mix usage_rules.search_docs "search term" -p usage_rules
```

## Available Mix Tasks

- `mix usage_rules.docs` - Shows documentation for Elixir modules and functions
- `mix usage_rules.install` - Installs usage_rules
- `mix usage_rules.list` - Lists usage-rules.md and sub-rules (usage-rules/*.md) for dependencies
- `mix usage_rules.search_docs` - Searches hexdocs with human-readable output
- `mix usage_rules.sync` - Sync AGENTS.md and agent skills from project config
- `mix usage_rules.validate` - Validates references in usage-rules-managed files
<!-- usage-rules-skill-end -->
