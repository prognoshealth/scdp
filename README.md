# Supply Chain Dependency Protection

Protect your development machine from supply chain attacks with three layers of defense:

1. **Release-age gating** — Package managers won't install packages published less than 7 days ago, blocking most attacks that rely on quick adoption of malicious packages.
2. **Install-script blocking** — Lifecycle scripts (`preinstall`, `install`, `postinstall`) are disabled by default in npm, pnpm, yarn, and bun, neutralizing the most common payload-delivery mechanism even if a malicious package slips through.
3. **Malware scanning** — Socket's `sfw` intercepts package manager commands and blocks known malware before it reaches your machine.

## Quick Start

```bash
./scripts/check-status.sh    # See what's currently protected
./scripts/setup.sh           # Set up everything
```

## What Is a Supply Chain Attack?

Modern software is built on **dependencies** — third-party packages pulled from public registries like npm, PyPI, and crates.io. A typical project may have hundreds of transitive dependencies, each maintained by independent developers.

A **supply chain attack** targets these dependencies rather than your code directly. Common vectors include:

- **Typosquatting** — publishing malicious packages with names similar to popular ones (`lodahs` instead of `lodash`)
- **Account takeover** — compromising a maintainer's account and publishing a backdoored update
- **Dependency confusion** — exploiting how package managers resolve private vs public package names
- **Malicious post-install scripts** — packages that run code during `npm install` before you've reviewed anything

### A Real Example: Axios (March 2026)

[Axios](https://socket.dev/blog/axios-npm-package-compromised) — an HTTP client with 100 million weekly npm downloads — was compromised when an attacker used a leaked npm token to publish malicious versions (`1.14.1` and `0.30.4`) directly to npm, bypassing the project's normal GitHub release process. The poisoned versions added a trojanized dependency (`plain-crypto-js`) that ran a post-install script deploying a remote access trojan with platform-specific payloads for macOS, Windows, and Linux. It enabled arbitrary command execution, exfiltrated system data, and then self-destructed to erase evidence.

Security researchers detected it within six minutes — but anyone who ran `npm install` during that window was compromised. Release-age gating would have blocked these versions entirely since they were minutes old, not days.

### Why This Is Getting Worse

The frequency and sophistication of supply chain attacks is accelerating:

- **More code, faster** — AI coding assistants generate and suggest dependencies at a pace humans can't individually vet. An AI agent running `npm install` doesn't pause to check if a package was published 10 minutes ago.
- **Larger attack surface** — the average JavaScript project pulls in 200+ transitive dependencies. Each is a potential entry point.
- **Low barrier to publish** — anyone can publish a package to npm or PyPI in minutes with no review process.
- **Automation of attacks** — attackers use automation to publish thousands of malicious packages targeting popular names, known dependency confusion patterns, and trending libraries.
- **Speed of adoption** — CI/CD pipelines and lockfile updates pull new versions automatically, often within hours of publication.

The defenses in this toolkit — **release-age gating**, **install-script blocking**, and **malware scanning** — directly counter the most common attack pattern: publish a malicious package, exploit its lifecycle scripts to run code at install time, and rely on fast, unreviewed adoption.

## Scripts

Each script is standalone — run them individually or use `scripts/setup.sh` to run everything.

### `scripts/check-status.sh`

Shows the current state of your protections: which package managers have age gating configured, which are wrapped with sfw, and what needs attention. Read-only — changes nothing.

### `scripts/setup-age-gating.sh`

Configures two protective defaults in package manager config files:

- **Release-age gating** — a 7-day minimum, so newly published packages are delayed before they can be installed.
- **Install-script blocking** — lifecycle scripts (`preinstall`, `install`, `postinstall`) are disabled for third-party dependencies in the Node ecosystem. Trade-off and recovery covered in [Install-script blocking](#install-script-blocking) below.

| File | Age-gating setting | Script-blocking setting | Tool |
|------|---------------------|--------------------------|------|
| `~/.npmrc` | `min-release-age=7` | `ignore-scripts=true` | npm (>=11.10) |
| `~/Library/Preferences/pnpm/rc` (macOS) | `minimum-release-age=10080` | `ignore-scripts=true` | pnpm (>=10.16) |
| `~/.yarnrc.yml` | `npmMinimalAgeGate: "7d"` | `enableScripts: false` | yarn (>=4.10) |
| `~/bunfig.toml` | `minimumReleaseAge = 604800` | `ignoreScripts = true` | bun (>=1.3) |
| `~/.config/uv/uv.toml` | `exclude-newer = "7 days"` | — | uv |

Configs are written proactively even if the tool isn't installed yet — they'll take effect when it is. If an outdated version is detected, the script warns loudly with the upgrade command.

### `scripts/setup-pip.sh`

Adds shell functions that wrap `pip` and `pip3` with `--uploaded-prior-to` for age gating. If `sfw` is on PATH, it's used automatically for malware scanning too. Works with or without sfw.

pip is handled separately because it has no config file support for age gating — a shell wrapper is the only option.

### `scripts/install-sfw.sh`

Installs Socket Firewall Free (`sfw`) globally via npm. sfw is a proxy that scans packages against Socket.dev's malware database before allowing installation. Requires npm.

### `scripts/setup-shim.sh`

Adds shell functions that route package manager commands through sfw. Requires sfw to be installed first (run `scripts/install-sfw.sh`). Wraps: npm, npx, yarn, pnpm, uv.

Does **not** wrap pip — that's handled by `scripts/setup-pip.sh`.

### `scripts/setup.sh`

Runs everything in order:
1. `scripts/setup-age-gating.sh` — config files
2. `scripts/setup-pip.sh` — pip shell wrapper
3. `scripts/install-sfw.sh` — install sfw binary
4. `scripts/setup-shim.sh` — sfw shell wrappers

Pass `--no-shim` to skip steps 3 and 4 (age-gating only, no sfw).

## Shell Config

The scripts detect **all existing** RC files and write to each one, so protections work regardless of which shell you open:

- `~/.zshrc`
- `~/.bashrc`
- `~/.bash_profile`

If none exist, one is created for your login shell (`$SHELL`).

Two sentinel-delimited blocks may be added:

- `# >>> sca-pip-age-gating >>>` — pip/pip3 age-gating wrapper
- `# >>> sca-shim >>>` — sfw wrapper functions for npm, npx, yarn, pnpm, uv

All files are backed up to `<filename>.bak.<timestamp>` before modification.

## Reverting

1. Restore config files from `.bak` backups:
   ```bash
   # Example: restore .npmrc
   cp ~/.npmrc.bak.20260401120000 ~/.npmrc
   ```

2. Remove shell blocks from your RC files:
   ```bash
   # Remove pip age-gating
   sed -i '' '/# >>> sca-pip-age-gating >>>/,/# <<< sca-pip-age-gating <<</d' ~/.zshrc
   # Remove sfw shims
   sed -i '' '/# >>> sca-shim >>>/,/# <<< sca-shim <<</d' ~/.zshrc
   ```

3. Uninstall sfw: `npm uninstall -g sfw`

## AI Coding Agents

This toolkit is designed to protect your development machine during normal day-to-day work. The sfw shell wrappers and pip age-gating function are defined as aliases/functions in your shell RC files (`~/.zshrc`, `~/.bashrc`). Some AI coding agents (e.g. Claude Code in normal use) source your shell profile and will pick up the wrappers automatically; others may not.

If your agent doesn't load your shell profile, the wrappers are silently skipped and commands hit the package manager directly. To provide protection, add something like this to your system prompt or project instructions:

> When running package install commands, always prefix them with `sfw` to route through the Socket Firewall for malware scanning. For example, use `sfw npm install <pkg>` instead of `npm install <pkg>`. This applies to npm, npx, yarn, pnpm, uv, and pip.

## Install-script blocking

Most malicious npm packages don't wait to be `require()`d — they execute via a `postinstall` (or `preinstall`/`install`) script the moment `npm install` runs. That's how the Axios compromise dropped its RAT: a trojanized transitive dependency's postinstall ran before anyone could review a single line. Setting `ignore-scripts` globally neutralizes this class of attack — the script is on disk but never invoked.

The trade-off: some packages legitimately need their install script to compile native code or download platform-specific binaries. Common examples include `esbuild`, `sharp`, `better-sqlite3`, `node-sass`, and `node-gyp`-based modules. When these are installed under a blocked-scripts default, the install completes but the package won't actually work until you rebuild it.

### Rebuilding a package you trust

Once you've vetted the package, run the rebuild command for your package manager:

| Manager | Command |
|---------|---------|
| npm | `npm rebuild <pkg>` |
| pnpm | `pnpm rebuild <pkg>` (or `pnpm approve-builds` to allowlist interactively) |
| yarn | `yarn rebuild [<pkg>]` |
| bun | `bun pm trust <pkg>` (adds to `trustedDependencies` and rebuilds) |

For projects you control, you can also list known-good packages in `package.json` so they always build:

- **pnpm**: `pnpm.allowedDeps` (newer) / `pnpm.onlyBuiltDependencies` (older) in `package.json`.
- **bun**: `trustedDependencies` array in `package.json`.
- **yarn** / **npm**: no per-package allowlist — rebuild explicitly after install.

## Known Limitations

- **pip**: Age-gating only works in interactive shell sessions (shell function wrapper). CI/scripts need the `--uploaded-prior-to` flag explicitly.
- **Go**: No native age-gating support. Use manual review and checksum verification.
- **sbt/Scala**: No native age-gating support. Pin exact versions in `build.sbt`.
- **sfw free tier**: Covers npm, yarn, pnpm, pip, uv, cargo. Does **not** cover Go or JVM packages.
- **sfw**: Only blocks confirmed (human-reviewed) malware in the free tier. AI-flagged suspicious packages are warned but not blocked.

## Supported Ecosystems

| Ecosystem | Age Gating | Script Blocking | sfw Scanning |
|-----------|-----------|------------------|-------------|
| npm/Node.js | config file | config file (`ignore-scripts`) | sfw shim |
| pnpm | config file | config file (`ignore-scripts`) | sfw shim |
| yarn (v4+) | config file | config file (`enableScripts: false`) | sfw shim |
| bun | config file | config file (`ignoreScripts`) | — |
| pip/Python | shell wrapper | n/a (`setup.py` runs inherently) | via setup-pip.sh |
| uv | config file (rolling 7-day window) | n/a | sfw shim |
| Go | not available | n/a | not covered (free tier) |
| sbt/Scala | not available | n/a | not covered (free tier) |
| Rust/Cargo | — | n/a | supported by sfw |
