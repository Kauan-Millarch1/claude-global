---
name: read-plugin-metadata-without-installing-the-package
problem-shape: you need the machine-readable metadata a plugin ecosystem publishes (parameter schemas, enums, per-version shapes) but the metadata is embedded in compiled plugin code, and installing the ecosystem to read it is disproportionate or forbidden by the project's dependency rules
transferable-to: any ecosystem whose plugins are compiled TS/JS declaring themselves in code rather than in a data file — n8n nodes, ESLint plugin rules, Rollup/Vite/Webpack plugins, VS Code extension contributions, Terraform providers via their JS wrappers, Home Assistant custom components. Also: any "generate valid config for X" task where the generator is guessing X's schema from training memory
verified-by: 810 node types distilled from 3 npm packages with zero file-load failures; the gate built on top of it flagged 0% of the project's own working flows and 1.3% of 2560 nodes across 99 published third-party flows, with the remainder confirmed as genuine stale-parameter defects
date: 2026-08-12
---

## What failed first

Three approaches, each plausible, each wrong:

1. **Ask the running instance for its schema.** The editor UI clearly has this data, so an
   endpoint must serve it. It does — and it is session-authenticated. The API-key path returned
   401/404 on every candidate. *Generalisation: the endpoint the product's own frontend uses is
   usually not part of the public contract.*
2. **Install the package and require it.** Correct output, disproportionate cost: ~83MB and
   26k files, plus a runtime dependency in a project whose whole identity was zero dependencies.
3. **Take a third party's prebuilt database of the same metadata.** Fastest, and it makes
   someone else's build artifact the source of truth about the ecosystem, versioned on their
   schedule, when the primary source is one command away.

Then the extraction itself failed **silently**, which was worse than failing loudly: a
constructor that throws was skipped with no counter, so 11 plugin types — including the two most
used — simply were not in the output. Downstream, absence read as "this type does not exist" and
the gate built on it started rejecting valid input.

## What worked

**Fetch the package without its dependency tree, then load the compiled module with its imports
stubbed.** `npm pack` (not `install`) yields a tarball carrying every compiled plugin file and
no `node_modules`; hang a hook on the module loader that returns a Proxy for anything that fails
to resolve, then `require` the file and read the descriptor off `new Cls()`.

It works because a plugin's *self-description* is built in the constructor from literals, while
its *behaviour* is what needs the real dependencies. Stubbing separates the two.

Four mechanisms make the difference between 90% and 100%:

- **Stub the framework's few semantic helpers for real.** Most imports can be a Proxy, but the
  one or two helpers that *transform the declaration* cannot: here a function that injects the
  conditional-visibility predicate into a property list. Proxied, it returns a non-iterable and
  the constructor dies — losing exactly the information the whole exercise was for. **The helper
  you are tempted to stub is often the one carrying the payload.**
- **The stub must claim `__esModule: true`.** Counter-intuitive: the TypeScript `__importStar`
  helper, when that flag is false, *copies enumerable keys* into a fresh object — and a Proxy
  over a function has only `length`/`name`/`prototype`, so the copy silently discards the stub.
  Claiming ES-module-ness makes the helper pass the module through untouched.
- **The stub must be iterable** (empty generator). Descriptors spread helper results into
  arrays; non-iterable kills the whole plugin, empty merely drops those entries. Degrade, don't
  die.
- **Class-based version wrappers need a real base class.** Whatever type holds the
  version→implementation map must be a genuine constructor that stores its arguments, or every
  multi-version plugin collapses to an object with no keys.

And the two disciplines that make the result trustworthy:

- **Do it in a child process.** Patching the module loader in the process that serves the app is
  reckless; the child dies with the hook inside it.
- **Count and name what failed to load.** Absence is downstream-indistinguishable from
  non-existence, and anything gating on this metadata will convert that into a false rejection.

## Tell

You are about to write "the schema for X is roughly…" from memory, or you are reaching for a
third-party mirror of metadata that X's own package already ships. Also: a validator you built
from that metadata starts rejecting inputs you know are good — that is not the validator being
strict, it is the extraction having lost entries without saying so.

The cheapest first probe: `npm view <pkg> dist.unpackedSize` and unpack one plugin file. If the
declaration is object literals in a constructor, this pattern applies.

Corollary worth keeping: metadata like this is **immutable per package version**, so cache it
keyed by version and re-fetch only on upgrade. And when a validator is built on top, make it
fail *open* on every gap — unknown type, approximate version, undecidable predicate — because a
gate that fires on missing knowledge blocks good work, which is worse than the defect it hunts.

Related: [[per-checkout-tool-state-fails-in-fresh-worktree]]
