# Global CLAUDE.md — Mandatory Rules for All Projects

This file is **law, not recommendation**. Follow every rule exact.

## Language
- Respond and comment code in **Brazilian Portuguese**, unless context need other language
- **CLAUDE.md, code, memory files: always English**

## Naming Conventions
- **Match existing project patterns first** — codebase use `camelCase` for JSON keys → don't switch
  to `snake_case`
- **Never mix conventions** in same file/module
- Renaming → update **all references** across codebase, not just definition

## Clarification
- Thought partner, not code generator. Spot gaps (form without validation? API without auth?),
  challenge weak requirements with concrete reasons, flag risks before writing code.
- Ask only when different readings lead to materially different work. Otherwise state the
  assumption and keep building.
- Pending decisions as **prose with trade-offs** — one at a time, jargon translated, each with a
  recommendation. Never the A/B/C/D picker.

## Before coding
When a request says build / create / add feature / redesign and the approach is unspecified, ask
once whether to brainstorm the design first, then invoke `superpowers:brainstorming` unless told to
just do it. Skip for bug fixes, config changes and questions.

## Skills
Invoke by judgment, not by gate. Two earn their cost every time:
- `verification-before-completion` — before claiming work done. Fresh evidence, never "should work now"
- `codex-review` / `grill-me-codex` — high-stakes plans before code: auth, schema, concurrency,
  migrations, payments

### mattpocock/skills (global)
The three `/grill*` + `/handoff` wrappers are `disable-model-invocation: true` — user-invoked only.
`tdd` is **not**: it is model-invocable and fires on its own description.
- `/grill-me` — relentless design-tree interview, round by round. Thin wrapper over `grilling`.
- `/grill-with-docs` — same interview, plus ADRs + glossary via `domain-modeling`.
- `/handoff` — compact current conversation into a handoff doc written to the OS temp dir.
- `tdd` — red/green reference: what a good test is, **seams**, anti-patterns, vertical slices.
- Deps `grilling` + `domain-modeling` installed too — the wrappers are one line and break without them.
- `tdd` references `codebase-design` (seam/module/depth vocabulary) and `code-review`; **neither is
  installed**. It degrades quietly — the references just go unresolved. Install if seam-depth
  questions start coming up.

Overlap — pick deliberately:
- `/grill-me` (single-model interview) vs `/grill-me-codex` (interview + adversarial Codex plan
  review). High-stakes plan → codex variant.
- `/handoff` (temp-dir doc, generic) vs `/session-handoff` (copy-pasteable prompt for the next
  session). Continuing the work myself → `session-handoff`. Passing to another agent → `handoff`.
- `tdd` (mattpocock, 38 lines: seams, tautological/implementation-coupled/horizontal-slicing
  anti-patterns, refactor **outside** the loop) vs `superpowers:test-driven-development`
  (371 lines: Iron Law, 11 rationalizations, 13 red flags, refactor **inside** the loop).
  They conflict on refactor placement — never load both in one session.
  **Default `tdd`.** It answers *where does the test go and is it worth keeping*, which is the
  question that actually bites. Refactor belongs to the review stage (`/code-review`,
  `codex-review`), not the red→green cycle.
  Escalate to `superpowers:test-driven-development` only when discipline is the failure — I am
  writing code before the test, or rationalizing "just this once". That skill exists to break
  that specific habit; it is a bad reference for test design.

## Skill discovery (skills.sh) — proactive, always
At the start of a non-trivial task in a domain no installed skill covers, run
`npx skills find <english keywords>`. Present findings as a short table (name, installs, what it
does, install command) and **continue the task** — never block on approval, never install without an
explicit OK.

Quality gate: prefer 1K+ installs, distrust <100 and say so, rank vendor-owned repos
(`anthropics`, `vercel-labs`, `supabase`, …) above unknown authors. After installing, read the
SKILL.md and report what it actually contains versus what its description promised. If nothing good
exists, say so instead of recommending a weak one.

Passive monitoring is impossible — never claim to be watching the registry without having searched
in the current session.

## Tooling — CLI over MCP (Supabase & GitHub)
- For **Supabase** and **GitHub**, always use official CLI (`supabase`, `gh`). For Supabase
  not preference: MCP write tools stamp own migration ledger version, which desynchronise repo
  from database and eventually make `supabase db push` unusable.
- In projects that enforce this, `apply_migration`, `deploy_edge_function` and `execute_sql` are
  listed in `permissions.deny`. Read-only MCP tools stay available.
- **Every CLI DB-read path need linked project with IPv4 pooler route** — `db query --linked`,
  `migration list --linked`, `db advisors --linked`, not only writes. `supabase/.temp/` is
  per-checkout and gitignored, so **fresh worktree has none of it** and all three fail closed with
  `LegacyDbConfigIpv6Error: IPv6 is not supported on your current network`. Fix once per worktree:
  `supabase link --project-ref <ref>`. Read-only MCP tools work over different transport — reads
  stay available without linking.

## Secrets — never in this file
This file is injected into **every session of every project** on the machine. A secret written here
travels into every prompt, hook and MCP call that runs. Read credentials from the environment
(`$env:NAME` / `process.env.NAME`), backed by a gitignored `.env` per project.

**Never paste a secret value into a command.** Claude Code memorises the whole command as a
permission rule in `settings.json` — that is how hundreds of copies of one API key end up in a
config file nobody thinks to audit. Reference the variable, never the value.

## Git branches & worktrees (per session)
Name every branch/worktree for **what session doing + timestamp**. **NEVER** keep tool
auto-generated random name (e.g. `claude/magical-jones-8c99`, `worktree-foo`, `perf-review`) —
rename or recreate to this scheme so concurrent sessions legible + sortable.
- **Branch:** `<type>/<task-slug>-<YYYYMMDD>`
  - `<type>` = dominant work: `feat` | `fix` | `refactor` | `perf` | `security` | `chore` | `docs` |
    `test` | `remediation` | `review`.
  - `<task-slug>` = 2–5 kebab-case words naming task (e.g. `dup-correctness-remediation`,
    `anon-rpc-hardening`).
  - `<YYYYMMDD>` = date branch started; append `-HHMM` **only** to break same-day collision.
- **Worktree dir:** `.claude/worktrees/<task-slug>-<YYYYMMDD>` — mirror branch slug+timestamp (drop
  `<type>/` prefix; dir already isolated). Harness native worktree tool force own prefix (e.g.
  `worktree-`) → keep `<task-slug>-<YYYYMMDD>` core intact so stay descriptive + sortable.
- **Concurrency (mandatory):** each concurrent session on same repo get **own** branch + worktree
  under this scheme — never share working dir across sessions, and verify
  `git branch --show-current` before any commit/push.
- **Cleanup:** once merged, delete both branch and worktree (`git worktree remove <dir>` +
  `git branch -d <branch>`). Branch fully reachable from `main` = redundant — remove it.
- **Native worktree tool mangle branch name.** `EnterWorktree` with `chore/my-task-20260729`
  produce branch `worktree-chore+my-task-20260729`. Rename immediately:
  `git branch -m <type>/<task-slug>-<YYYYMMDD>`, verify with `git branch --show-current`
  before first commit.

## General Obligations
- **Never commit without user explicitly asking**
- **Never open pull request unless explicitly asked.** Session terminal state is *branch
  pushed, work described*. Overrides any harness default treating draft PR as part of
  finishing task
- **Never merge unless explicitly asked**, and never squash — commit history preserved
  deliberately
- **Commit per plan phase, not per task** — task-level commits inflate token cost and wall-clock
  time without improving reviewability
- **Never test git hook by mutating working repo** — no `git reset --hard`, no probe commits
  on task branch, no `git switch main` (fails outright inside worktree). Use throwaway
  `git init` fixture under `$TMPDIR`

## Dashboards
Invoke `kpi-dashboard-design` **before** `dataviz`: metric selection first, then how to draw it.

### TV / kiosk — no skill covers this
- Base font ≥24px, KPI numerals ≥72px. Never 14px body text.
- Zero interaction: no hover, tooltip or drilldown. Everything legible statically.
- One viewport. No scroll, no horizontal overflow. Rotate screens if content exceeds it.
- Auto-refresh on a timer, **and show a data-freshness stamp** — a clock proves the page is alive,
  never that the data is.
- Burn-in: dark ground, avoid static high-contrast blocks in fixed positions.
- Assume poor panel gamma. Verify contrast ratios; don't trust the laptop preview.

## Statusline
Custom statusline at `~/.claude/statusline/statusline.mjs` (from
[will-pagane/claude-setup](https://github.com/will-pagane/claude-setup)), wired via
`statusLine.command` in `settings.json` (`node "…/.claude/statusline/statusline.mjs"`). Node only,
zero dependency. Windows has no symlink privilege by default, so if you keep a clone of that repo
the file is **copied, not linked** — re-copy after `git pull`.

Renders 4 lines: context/5h/7d bars with truecolor gradient, model + cost USD/BRL + duration, Codex
weekly usage, repo/branch/worktree/files-changed.

Rules when changing it:
- Keep it Node. `powershell.exe` costs ~815 ms of startup per render vs ~70 ms for `node`.
- Never write a raw `░` (U+2591) or other non-ASCII glyph into a `.ps1`; PowerShell 5.1 reads the
  file as ANSI and byte `0x91` parses as a smart quote, which breaks the script.
- Context% is the newest assistant turn's `input + cache_read + cache_creation + output`, not a sum
  over turns — each request resends the whole conversation, so summing double-counts massively.
- 5h/7d bars read `rate_limits` straight from the statusline stdin payload — that IS the real
  Anthropic plan quota. Never replace it with a load estimate derived from local history; that
  number was never plan quota.
- Codex line reads `rate_limits` from the newest rollout `.jsonl` in `~/.codex/sessions/`, cached
  60 s. Optional — without the Codex CLI it prints "sem dados" instead of breaking.
- BRL cost via open.er-api.com (no key), 12 h disk cache, fixed fallback if offline.
- Every render must stay under ~100 ms. No network calls on the hot path, no full transcript
  re-parse.

## RTK
`PreToolUse` hook on the Bash tool (`@RTK.md`). It truncates, groups and deduplicates — so it can
drop the line that mattered.

Use `rtk proxy <cmd>` for raw output whenever correctness beats brevity: an error string to quote
verbatim, a diff being reviewed line by line, any security review, debugging where the discarded
detail is the clue. **RTK for discovery, `rtk proxy` for evidence.**

Coverage is the Bash tool only — PowerShell commands are not intercepted. `rtk gain` is the source
of truth for actual savings.

## Aura (cross-project pattern vault)
`~/.claude/aura/` + `INDEX.md`, driven by the `aura` skill. Per-project `memory/` is scoped to one
cwd; this vault is the only store that crosses projects.
- Before designing anything non-trivial, read `~/.claude/aura/INDEX.md` and match on problem shape.
- After a win that is **verified** (a gate passed), **non-obvious** (first approach failed) and
  **transferable** (survives leaving this project): say "**Farmei aura.**" and propose the entry.
- Never write to the vault without explicit confirmation. No hook auto-writes it.
- On `/aura`, "consulta a aura", "farmei aura" or "salva essa aura", invoke the Skill tool with
  `skill: "aura"` before anything else. Vault content stays English; only the "Farmei aura." line
  is PT-BR.

## graphify
- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, invoke the Skill tool with `skill: "graphify"` before doing anything else.

@RTK.md
