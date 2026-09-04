# claude-global

A portable Claude Code global setup: working rules, agents, skills, a statusline, and the plugin manifest that pulls the rest in.

Clone it, run one script, restart Claude Code.

```powershell
git clone https://github.com/Kauan-Millarch1/claude-global.git
cd claude-global
.\install.ps1 -WhatIf     # see the plan, change nothing
.\install.ps1             # do it
```

## What you get

**The rules** — `CLAUDE.md` is the centre of gravity. It is not a style guide; it is a set of standing instructions that change how the agent behaves: ask before building when the approach is unspecified, never commit or open a PR unbidden, name branches by task and date, prefer the official CLI over MCP write tools for Supabase and GitHub, present pending decisions as prose with a recommendation rather than a multiple-choice picker.

**Agents** (`agents/`) — a five-stage pipeline where each stage is denied the tools that would let it cheat:

| Agent | Does | Cannot |
|---|---|---|
| `ae-scout` | read-only recon before planning | write anything but its own report |
| `ae-planner` | numbered plan, each step independently verifiable | touch source |
| `ae-build` | implements one step, loops against the gates | weaken a gate to pass it |
| `ae-test` | writes tests from acceptance criteria, mutation-tests them | fix the source bugs it finds |
| `ae-reviewer` | adversarial review, verdict + repro | write source |

**Skills carried in this repo** — `graphify` (anything to a queryable knowledge graph), `codex-build`, `grill-me-codex` and `grill-with-docs-codex` (plan interview plus an adversarial second-model review before code), `web-artifacts-builder`.

**Skills installed from their real sources** — `install.ps1` runs `npx skills add` and `claude plugin install` instead of copying, so they stay updatable by their authors: `superpowers`, `caveman`, `impeccable`, `learning-output-style`, mattpocock's `grilling` / `grill-me` / `grill-with-docs` / `handoff` / `domain-modeling` / `tdd`, `find-skills`, the Supabase pair, and will-pagane's `codex-review` / `session-build` / `session-handoff` / `code-ultragraph-review`.

**`eyes`** — clones [Kauan-Millarch1/claude-eyes](https://github.com/Kauan-Millarch1/claude-eyes) and installs its runtime. Opens a real browser, uses the UI like a person, and publishes the review as a shareable page with the screenshots embedded.

**A statusline** (`statusline/statusline.mjs`, from [will-pagane/claude-setup](https://github.com/will-pagane/claude-setup)) — four lines: context and quota bars, model with cost in USD/BRL, Codex weekly usage, repo/branch/worktree. Node only, no dependencies, renders in about 70 ms.

**An `aura` vault** (`aura/`) — cross-project pattern notes. Two entries seeded; it is meant to grow.

## Requirements

**Required:** Node 18+, git, Claude Code.

**Recommended:**
- **`rtk`** — the `PreToolUse` hook shells out to it to compress Bash output. **If you do not install it, remove the `PreToolUse` block from `~/.claude/settings.json`** — leaving the hook in place without the binary makes every Bash call fail. `RTK.md` explains what it does and when to bypass it with `rtk proxy`.
- **`gh`** — several skills and the CLAUDE.md rules assume it.
- **`codex`** (OpenAI CLI) — only the `*-codex` skills need it. They are the ones that get a second model to attack your plan before you write code.
- **Chrome or Edge** — only for `eyes`.

## What the installer does

1. **Preflight** — checks `node` and `git`, reports each optional tool as found or missing with a reason.
2. **Copies** `CLAUDE.md`, `RTK.md`, `agents/`, `aura/`, `statusline/`, and this repo's skills into `~/.claude/`. Anything it would overwrite is backed up to `<file>.bak-<timestamp>` first, and files that already match are skipped.
3. **Merges** `settings.template.json` into your existing `~/.claude/settings.json`. It never overwrites the file: `permissions.allow` and `permissions.deny` are unioned, so rules you already approved survive. The `__CLAUDE_HOME__` placeholder in the statusline command is resolved to your real path.
4. **Installs** the third-party marketplaces, plugins and skills from their own sources.
5. **Clones** `claude-eyes` and runs `npm install` in its runtime.

Run `.\install.ps1 -WhatIf` first. It prints every action and changes nothing.

### On macOS and Linux

There is no `install.sh` — it would ship untested. Do it by hand:

```bash
cp CLAUDE.md RTK.md ~/.claude/
cp -r agents aura statusline ~/.claude/
cp -r skills/* ~/.claude/skills/

npx skills add mattpocock/skills
npx skills add vercel-labs/skills
npx skills add supabase/agent-skills

claude plugin marketplace add obra/superpowers
claude plugin install superpowers@superpowers-dev
# same for JuliusBrussee/caveman, pbakaus/impeccable, anthropics/claude-code

git clone --depth 1 https://github.com/will-pagane/claude-setup.git ~/.claude/claude-setup
cp -r ~/.claude/claude-setup/skills/* ~/.claude/skills/

git clone --depth 1 https://github.com/Kauan-Millarch1/claude-eyes.git ~/.claude/skills/eyes
(cd ~/.claude/skills/eyes/runtime && npm install)
```

Then merge `settings.template.json` into `~/.claude/settings.json` by hand, replacing `__CLAUDE_HOME__` with your `~/.claude` path and dropping the `_`-prefixed comment keys.

## About the permissions

`settings.template.json` ships **30 allow rules**, all read-only or trivially reversible, plus three `deny` entries that enforce the CLI-over-MCP rule for Supabase migrations.

That is deliberate, and it is the part worth understanding before you copy anyone else's setup.

Every time you approve a command in Claude Code, the **entire command string** is memorised as a permission rule. After a few months that list is a log of everything you ran: internal URLs, resource IDs, absolute paths, hostnames. The setup this repo was extracted from had **858 rules and a 130 KB `settings.json`** — 96% of the file was permissions, and hundreds of them named a private automation host and its workflow IDs.

So: none of that is here, and you should not import anyone's allowlist either. Build your own as Claude asks. It takes a week and it stays yours.

The same reasoning applies to secrets. `CLAUDE.md` is injected into **every session of every project** on the machine, so a key written there travels into every prompt, hook and MCP call. Read from the environment, back it with a gitignored `.env`, and never paste a value into a command — the command becomes a permission rule, and that is exactly how hundreds of copies of one API key end up inside a config file nobody audits.

## What is deliberately not here

- **Company-specific skills.** The source setup had an N8N reliability orchestrator and a client-meeting prep skill, both wired to one company's infrastructure. They would leak that infrastructure and would not run for you.
- **`settings.json` itself.** See above.
- **Credentials.** `~/.claude/.credentials.json` is never in scope.
- **`kpi-dashboard-design`** — it lives inside `wshobson/agents`, a large repo. Add it yourself with `npx skills add wshobson/agents` if you want it.

## Layout

```
CLAUDE.md                the rules, injected into every session
RTK.md                   how the Bash-output compressor behaves and when to bypass it
install.ps1              idempotent installer, backs up before touching anything
settings.template.json   plugins, hooks, statusline, minimal permissions
agents/                  ae-scout / ae-planner / ae-build / ae-test / ae-reviewer
aura/                    cross-project pattern vault
skills/                  the skills carried here rather than installed from upstream
statusline/              statusline.mjs
```

## Credits

`statusline.mjs` and the `codex-review` / `session-*` / `code-ultragraph-review` skills are from [will-pagane/claude-setup](https://github.com/will-pagane/claude-setup). The `grill*` family builds on [mattpocock/skills](https://github.com/mattpocock/skills) (MIT) — the `*-codex` variants add the second-model review and carry their own `THIRD-PARTY-NOTICES.md`. `superpowers` is [obra/superpowers](https://github.com/obra/superpowers), `caveman` is [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman), `impeccable` is [pbakaus/impeccable](https://github.com/pbakaus/impeccable).

## License

MIT — see [LICENSE](LICENSE). Bundled third-party skills keep their own licenses.
