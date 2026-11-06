# Drafts

Not wired into the image. Nothing here is copied by the Dockerfile (`drafts/` is not referenced and is excluded from the build context).

## `skills/`

Three starter skills for R work: `r-package-dev`, `r-renv-deps`, `r-debug-failing-tests`.

**Delivery is an open question.** `config/managed-settings.json` is validated to have `strictPluginOnlyCustomization: true` and `disableCommandPluginSources: true`. That probably means skills in `~/.claude/skills` or `<project>/.claude/skills` are ignored, and these would need to ship another way, for example as a plugin that the managed policy allows. Check this before wiring anything in.

## System prompt

The always-on instructions are `config/CLAUDE.md`, installed at `/etc/claude-code/CLAUDE.md`. Keep it short and put task-specific procedure in skills.
