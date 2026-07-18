# Agent instructions

## App Store Connect

For every task that reads or changes App Store Connect for this project, use the
`asc` CLI. Do not operate App Store Connect through a browser unless `asc`
explicitly lacks support for the requested action.

- The registered app name is `起きなはれ`.
- For build or upload requests, the local Ollama orchestration flow owns the
  checks for the App Store Connect app ID, next safe build number, user
  authorization, ASC profile, and bridge/runner configuration. Codex must not
  pre-resolve or choose those values.
- The fixed runner may make read-only ASC queries to supply safe facts to the
  local model, but credentials and private-key material must never be supplied
  to that model.
- Prefer keychain authentication through `asc auth login`; never place
  credentials, private keys, or their contents in repository files.
- Before any App Store Connect operation, read the Obsidian note
  `codex/ASCでiOSビルドをアップロードする方法.md` using the Obsidian CLI and
  follow the applicable steps. In particular, follow its authentication,
  build-number, archive, export, upload, and verification procedure before
  uploading a build.
- When Codex is asked to build or upload, use `scripts/asc-ollama-upload.sh` as
  the entry point. It delegates the scoped orchestration decision to the local
  Ollama model and then invokes the fixed runner; do not invoke the runner
  directly for normal operations. Never send credentials or private keys to the
  local model; the bridge and runner resolve and apply the appropriate profile.
- For a new build, the Ollama bridge and fixed runner obtain the next build
  number, then perform the version edit, archive, export, upload, and final
  `VALID` check. Codex must not perform those steps directly.
- Forward the user's original request unchanged with `--request`. Codex must
  not translate it into ASC commands, inspect detailed build logs, or diagnose
  failures. The bridge returns only a small JSON result with `status` set to
  `success` or `failure`; Codex only checks that status and reports it.

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
