# Research: Claude Code plugin skills and GitHub releases

Checked 2026-08-10. Provisional decision: treat “today” as current Claude Code local-plugin behavior. I would have asked whether the target was portable Skill API packaging; the recommended default is a Claude Code plugin skill, with portable constraints called out separately.

## 1. Plugin skill layout and loading

VERIFIED. The canonical multi-skill layout is:

```text
<plugin-root>/
├── .claude-plugin/
│   └── plugin.json                 # optional plugin manifest
└── skills/
    └── <skill-name>/
        ├── SKILL.md                # required entry point
        └── <supporting files...>   # optional
```

`skills/` is at the plugin root. `.claude-plugin/` contains only `plugin.json`; components placed in that directory are not found. A manifest is optional: default component locations are auto-discovered, and an omitted manifest derives the plugin name from the directory. Skills and commands are automatically discovered when the plugin is installed. Sources: [Create plugins](https://code.claude.com/docs/en/plugins.md), [Plugins reference](https://code.claude.com/docs/en/plugins-reference.md).

VERIFIED. A single-skill alternative is `<plugin-root>/SKILL.md`, with no `skills/` directory and no `skills` manifest field. Claude Code automatically loads that layout in v2.1.142 and later. A skill under `skills/` is invoked as `/plugin-name:skill-name`; its frontmatter `name` replaces only the final segment. Sources: [Plugins reference](https://code.claude.com/docs/en/plugins-reference.md), [Skills](https://code.claude.com/docs/en/skills.md).

## 2. Current skill frontmatter

VERIFIED. Claude Code accepts the following 19 fields. Its documentation says all are optional and `description` is recommended. `description` and `when_to_use` share a 1,536-character default listing cap. The source documents that cap as truncation in the skill listing, not input rejection. Source: [Skills frontmatter reference](https://code.claude.com/docs/en/skills.md#frontmatter-reference).

| Field | Required in Claude Code | YAML type or accepted values | Documented length limit |
| --- | --- | --- | --- |
| `name` | No | string | none |
| `description` | Recommended | string | shared 1,536-character listing cap |
| `when_to_use` | No | string | shared 1,536-character listing cap |
| `argument-hint` | No | string | none |
| `arguments` | No | space-separated string or YAML list | none |
| `disable-model-invocation` | No | boolean | none |
| `user-invocable` | No | boolean | none |
| `allowed-tools` | No | space- or comma-separated string, or YAML list | none |
| `disallowed-tools` | No | space- or comma-separated string, or YAML list | none |
| `model` | No | `/model` value or `inherit` | none |
| `effort` | No | `low`, `medium`, `high`, `xhigh`, or `max` | none |
| `context` | No | `fork` | none |
| `agent` | No | subagent-type string, used with `context: fork` | none |
| `background` | No | boolean, used with `context: fork` | none |
| `hooks` | No | YAML map in Hooks configuration format | none |
| `paths` | No | comma-separated glob string or YAML list | none |
| `shell` | No | `bash` or `powershell` | none |
| `metadata` | No | YAML map | none |
| `license` | No | scalar license value | none |
| `compatibility` | No | string | 500 characters |

VERIFIED. Boolean fields accept `true`/`false` and case-insensitive `yes`/`no`/`on`/`off`/`1`/`0`. Source: [Skills frontmatter reference](https://code.claude.com/docs/en/skills.md#frontmatter-reference).

CONTRADICTED. “`name` and `description` are required for a Claude Code plugin skill.” Current Claude Code makes both optional, although it recommends `description`. The separate [Agent Skills specification](https://agentskills.io/specification.md) requires those fields for portable spec-conformant skills and gives `name` a 64-character maximum and `description` a 1,024-character maximum. Claude Code also states that only the six standard fields are accepted by Claude.ai uploads, the Skills API, and `package_skill.py`; do not apply the Claude Code-only fields to that distribution path. Source: [Skills portability rules](https://code.claude.com/docs/en/skills.md#using-skill-frontmatter-outside-claude-code).

## 3. How descriptions trigger skills

VERIFIED. The documented rule is: “Claude uses this to decide when to apply the skill.” That sentence describes `description`. If it is omitted, Claude Code uses the first Markdown paragraph. `when_to_use` appends trigger phrases or examples to `description` in the listing. Source: [Skills frontmatter reference](https://code.claude.com/docs/en/skills.md#frontmatter-reference).

UNVERIFIABLE. Anthropic documents no deterministic matcher, score, threshold, or guarantee that a particular wording will invoke a skill. The published contract is description-based selection, not an algorithmic trigger specification. Source checked: [Skills](https://code.claude.com/docs/en/skills.md).

## 4. `gh release create`

VERIFIED. The current command surface is:

```text
gh release create [<tag>] [<filename>... | <pattern>...]
```

Its release-specific options are `--discussion-category <string>`, `-d|--draft`, `--fail-on-no-commits`, `--generate-notes`, `--latest[=false]`, `-n|--notes <string>`, `-F|--notes-file <file>`, `--notes-from-tag`, `--notes-start-tag <string>`, `-p|--prerelease`, `--target <branch>`, `-t|--title <string>`, and `--verify-tag`. It also inherits `-R|--repo <[HOST/]OWNER/REPO>`. Source: [GitHub CLI manual](https://cli.github.com/manual/gh_release_create).

VERIFIED. Attach release notes from a file with:

```bash
gh release create v0.5.0 --title v0.5.0 --notes-file release-notes.md
```

`-F release-notes.md` is equivalent, and `-F -` reads from standard input. Source: [GitHub CLI manual](https://cli.github.com/manual/gh_release_create).

VERIFIED. If the named remote tag does not exist, `gh` creates it from the latest state of the default branch. `--target <branch-or-SHA>` changes that target; `--verify-tag` instead aborts when the remote tag is absent. Fetch the generated tag locally with `git fetch --tags origin`. Source: [GitHub CLI manual](https://cli.github.com/manual/gh_release_create).

## 5. Changes since 2025-08-10

VERIFIED. The current plugin and skill model postdates the one-year cutoff: the Plugin System shipped on 2025-10-09 and Claude Skills on 2025-10-16. Source: [Claude Code changelog](https://code.claude.com/docs/en/changelog.md).

VERIFIED. Since then, the documented behavior changed as follows:

| Date and version | Current fact that earlier training can miss |
| --- | --- |
| 2026-01-07, v2.1.0 | automatic skill hot reload, `context: fork`, `agent`, and skill-frontmatter hooks were added |
| 2026-05-14, v2.1.142 | a root-level `SKILL.md` became a supported single-skill plugin layout |
| 2026-05-27, v2.1.152 | `disallowed-tools` was added |
| 2026-07-22, v2.1.218 | forked skills became background-by-default, with `background: false` as the opt-out; additional boolean spellings became valid |
| 2026-08-04, v2.1.221 | manifest `"skills": "."` became valid; use `"./"` when earlier compatibility matters |

Sources: [Claude Code changelog](https://code.claude.com/docs/en/changelog.md), [Plugins reference](https://code.claude.com/docs/en/plugins-reference.md).

VERIFIED. GitHub CLI documentation was clarified on 2025-08-25 that `--notes-from-tag` uses an annotation or, for an unannotated tag, the associated commit message; `--generate-notes` calls GitHub’s Release Notes API. This is documentation clarification, not evidence of a new flag. Source: [GitHub CLI commit 204536c](https://github.com/cli/cli/commit/204536cdd049559b7854fc4ab2430d102560d016).
