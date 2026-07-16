# Agent instructions

## App Store Connect

For every task that reads or changes App Store Connect for this project, use the
`asc` CLI. Do not operate App Store Connect through a browser unless `asc`
explicitly lacks support for the requested action.

- The registered app name is `起きなはれ`.
- Resolve and use its App Store Connect app ID before a command that requires
  `--app`; do not guess the ID from the app name.
- Use `asc --help` (and subcommand `--help`) before composing unfamiliar
  commands. Use `asc search` or `asc schema` when command or API fields are
  unclear.
- Prefer the current canonical verbs: `view` for reads and `edit` for updates.
- Use explicit long flags and a human-readable `--output table` or
  `--output markdown` when reporting results.
- Treat any state-changing operation as consequential: show the intended
  target and values first, and use `--confirm` only after the user has
  authorized that specific change.
- Prefer keychain authentication through `asc auth login`; never place
  credentials, private keys, or their contents in repository files.

## Obsidian work

For every task involving Obsidian in any project, always use the applicable
installed skills from `kepano/obsidian-skills` before taking action:

- `obsidian-markdown` for Obsidian-flavored Markdown
- `obsidian-bases` for `.base` files
- `json-canvas` for `.canvas` files
- `obsidian-cli` for Obsidian CLI and vault operations
- `defuddle` for extracting web pages into clean Markdown

Use every skill that applies to the task. Read each applicable `SKILL.md`
completely and follow it.
