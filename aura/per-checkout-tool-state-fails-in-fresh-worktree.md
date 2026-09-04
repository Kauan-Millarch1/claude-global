---
name: per-checkout-tool-state-fails-in-fresh-worktree
problem-shape: A CLI works in the original checkout and fails immediately in a fresh worktree or clone, with an error naming the transport/network/config rather than the missing link. The state it needs lives in a gitignored dir, so it never travels with the branch.
transferable-to: Any CLI holding per-checkout state in a gitignored dir — supabase, terraform, gcloud configurations, wrangler, vercel, fly. Any multi-worktree workflow.
verified-by: Same command failing in the new worktree and succeeding after re-linking, with no code change in between.
date: 2026-08-05
---

## What failed first
Reading the error literally. `LegacyDbConfigIpv6Error: IPv6 is not supported on your current
network` points at the network stack, so the instinct is to debug routing, DNS or IPv4 pooler
settings. All of that is a dead end — the network was never the problem.

The second wrong turn: assuming only writes need the linked project. Every read path
(`db query --linked`, `migration list --linked`, `db advisors --linked`) fails the same way.

## What worked
Recognizing the error as a *missing-state* error wearing a network costume. `supabase/.temp/`
holds the project link, is gitignored, and is therefore per-checkout — a fresh worktree has
none of it, so the CLI falls back to a legacy code path whose failure message describes the
fallback, not the cause. One `supabase link --project-ref <ref>` per worktree fixes all paths
at once.

Corollary that confirms the mechanism: MCP read-only tools kept working throughout. They use a
different transport and do not read the checkout-local state at all. When one client fails and
another succeeds against the same backend, the fault is in client-local state, never in the
backend or the network.

## Tell
The command worked yesterday, the only thing that changed is the directory, and the error names
a layer nobody touched. Check for a gitignored state dir before reading the error message
literally.
