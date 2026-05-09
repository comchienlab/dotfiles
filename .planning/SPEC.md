# SPEC: 9Router VPS Installer — Low-Spec Optimization & Interactive Rewrite

## Source Mode
files (refactor of `llm/setup_9router.sh`, 585 lines)

## Scenario
refine existing spec (rewrite an existing one-shot installer into a tiered, interactive, self-diagnosing tool)

## Goal
Rewrite `setup_9router.sh` into an interactive, gum-based VPS toolkit that reliably installs, updates, and self-checks a Next.js 9Router deployment on **1 GB RAM / 1 vCPU / 20 GB disk** Ubuntu VPS — the cheapest reliable tier — without OOM-killing the build or drifting out of tune over time.

## Users / Actors
- **Primary:** the repo owner (TINHTUTE) deploying 9Router to cheap VPS providers (Hetzner CX11, Vultr, Contabo $4-5/mo).
- **Secondary:** non-expert users who copy-paste a one-line `curl | sudo bash` command and pick options from a menu — must succeed without reading docs.
- **Not targeted:** Ansible/CI automation. Flag-driven non-interactive mode is explicitly deferred.

## Requirements

### R1. CLI shape — interactive menu
1.1 Single entrypoint script. When invoked with no args, shows a gum-based main menu.
1.2 Subcommands directly callable: `install`, `update`, `doctor`, `tune`, `status`, `logs`, `uninstall`, `rollback`.
1.3 Auto-installs `gum` if missing (apt repo or binary download), matching the pattern in `fsetup`/`fgit`.
1.4 Banner is preserved (current ASCII art) and shown above the main menu and at top of each subcommand.
1.5 All destructive actions (`uninstall`, `rollback`, applying `doctor` fixes) require explicit confirmation.

### R2. VPS spec detection — tiered tuning
2.1 On every run, detect: total RAM (MB), CPU cores, free disk (GB), OS distro+version, public IP, kernel version, swap state, zram availability.
2.2 Classify the VPS into one of three tiers:
   - **tiny** (<1024 MB RAM)
   - **small** (1024–2047 MB RAM) — default target
   - **medium+** (≥2048 MB RAM)
2.3 Each tier maps to its own sysctl values, journald cap, swap size, zram size, and systemd `MemoryMax` — see R5.
2.4 Detection results are printed in the banner header on every run.

### R3. Install flow (fresh install)
3.1 Reuses current 4-question prompt: domain, password, port, timezone — but rendered with `gum input` instead of bare `read`.
3.2 Build phase **stays on the VPS** (no upstream release dependency) but is hardened:
   - Pre-flight: refuse to start build if free RAM+swap < `MEM_LIMIT + 256MB` headroom.
   - Auto-create swap if missing; size = `2 × RAM` for tiny, `2GB` for small, `0` for medium+ (use existing swap or skip).
   - Enable **zram** on tiny/small tiers (compressed RAM swap, lz4, size = 50% of RAM, priority 100 — used before disk swap).
   - Dynamic `NODE_OPTIONS=--max-old-space-size=N` where N = `floor(RAM_MB / 2)` clamped to `[512, 1536]` (current behavior, kept).
   - Single retry on build failure: clear pnpm cache, drop caches (`echo 3 > /proc/sys/vm/drop_caches`), retry once.
3.3 All current security/network steps preserved (UFW idempotent, fail2ban, SSH keepalive).
3.4 Caddy + auto-HTTPS only when domain provided (current behavior, kept).
3.5 At end of install: print summary identical in spirit to current ending block, plus a hint to run `./9router doctor` weekly.

### R4. Update flow
4.1 Detect existing install via the same triple-check (`/etc/9router.env` + `/opt/9router/server.js` + systemd unit) as today.
4.2 Before pulling new code: snapshot `/opt/9router/.install-commit` to `/opt/9router/.previous-commit` for `rollback`.
4.3 Backup `/etc/9router.env` to `/etc/9router.env.bak.$(date +%s)` (keep last 5).
4.4 Build new commit; if build fails or `wait_for_service` fails, automatic rollback to previous commit (re-rsync from a kept-aside `/opt/9router-previous/` snapshot taken before deploy).
4.5 Single password-change prompt as today.

### R5. Tier-aware system tuning
5.1 Sysctl values sized per tier (concrete numbers locked in implementation, illustrative here):
   - **tiny:** `rmem_max=4M`, `wmem_max=4M`, `somaxconn=1024`, `netdev_max_backlog=2048`, `tcp_max_syn_backlog=2048`.
   - **small:** `rmem_max=8M`, `wmem_max=8M`, `somaxconn=4096`, `netdev_max_backlog=8192`, `tcp_max_syn_backlog=8192`.
   - **medium+:** current values (16M / 65535).
5.2 Common across tiers: `vm.swappiness=10`, `vm.overcommit_memory=1`, BBR + fq qdisc enabled (`net.core.default_qdisc=fq`, `net.ipv4.tcp_congestion_control=bbr`).
5.3 ulimits: keep `nofile=65535` for all tiers (file descriptors are cheap).
5.4 systemd unit gets `MemoryMax` and `MemoryHigh`:
   - **tiny:** `MemoryHigh=400M`, `MemoryMax=512M`.
   - **small:** `MemoryHigh=700M`, `MemoryMax=900M`.
   - **medium+:** unlimited (current behavior).
5.5 journald: `SystemMaxUse=200M`, `SystemMaxFileSize=50M`, `MaxRetentionSec=2week` (prevents log bloat on 20GB disks).
5.6 apt: `APT::Periodic::Unattended-Upgrade=1` for security patches (silent, weekly).

### R6. Doctor / autocheck
6.1 New `doctor` subcommand runs read-only health checks and prints a punch-list:
   - Service running (`9router.service`, `caddy.service` if applicable).
   - Disk free > 2 GB.
   - Free memory + swap > 200 MB.
   - Journal log size under cap.
   - Sysctl drift (compares running values against `/etc/sysctl.d/99-9router.conf`).
   - HTTPS cert validity > 14 days (if domain configured).
   - Pending security updates count.
   - zram active (on tiny/small tiers).
   - systemd `MemoryMax` matches current tier.
6.2 Each finding lists: severity (`OK` / `WARN` / `FAIL`), one-line description, the exact fix command.
6.3 If any finding is fixable automatically, prompt the user (one prompt per fix, with "fix all" shortcut) before applying. **Never modify silently.**
6.4 `doctor --json` flag emits machine-readable output for cron/monitoring.

### R7. Idempotence & safety
7.1 Every subcommand is safe to re-run.
7.2 Never `rm -rf` the data directory `/var/lib/9router` (current behavior, preserved).
7.3 Never reset existing UFW rules (current behavior, preserved).
7.4 Never overwrite `/etc/9router.env` without backup.
7.5 `uninstall` requires typing the install domain (or "9router" for IP-only) to confirm — protects against accidental removal.

### R8. Footprint targets
8.1 After install + cleanup on a 1 GB / 20 GB Ubuntu 24.04 VPS:
   - Disk used by 9router runtime + node + caddy: ≤ 600 MB.
   - RSS of `9router.service` at idle: ≤ 250 MB.
   - Total install time on 1 GB VPS: ≤ 8 min (current ~5–7 min, must not regress).

## Boundaries

### In Scope
- Refactor of `llm/setup_9router.sh` into a tiered, interactive, self-diagnosing toolkit (still a single shell script — no Go/Python rewrite).
- gum-driven menu and prompts.
- zram, BBR, tier-aware sysctl, systemd `MemoryMax`, journald cap, unattended-upgrades.
- Doctor / status / logs / tune / rollback / uninstall subcommands.
- Update flow with auto-rollback on build/start failure.

### Out of Scope
- Flag-driven non-interactive mode (deferred — see Deferred Ideas).
- Prebuilt-tarball deployment from upstream releases (deferred — requires upstream CI).
- Docker / containerized deploy.
- Build-on-remote-rsync-to-VPS flow.
- Multi-tenant or multi-domain deploys.
- Backup of `$DATA_DIR` (only env file is backed up; data backup left to user / external tool).
- Monitoring/alerting integration (Prometheus, Grafana). `doctor --json` is the integration point.
- Windows / non-Ubuntu host support (Debian 11/12 stays supported only because current script supports it; not a hard requirement).
- IPv6-specific tuning.

## Constraints
- **Language:** Bash (zsh-compatible for testing on macOS, but bash on target VPS). No new runtimes.
- **Dependencies on VPS:** must run on a fresh Ubuntu 22.04 / 24.04 with only `bash` + `curl` + `sudo`. Everything else (gum, node, pnpm, caddy) must be installable by the script.
- **Idempotent:** every subcommand re-runnable without breaking state.
- **Vietnamese + English mixed messages:** preserve current bilingual style of user-facing strings (current script mixes Vietnamese phrases like "Chế độ: Cập nhật" with English status). Do not switch to English-only.
- **Zero secret leakage:** `/etc/9router.env` stays `chmod 600`; no secret echoed to journald.
- **Upstream coupling:** continues to clone `decolua/9router` from main branch; if upstream changes build commands, this script must keep working without upstream coordination.

## Key Decisions

### D1. Build stays on-VPS (rejected: prebuilt tarball, hybrid, remote-build)
- **Chosen:** keep `pnpm install + pnpm build` on the VPS, harden with zram + headroom check + retry.
- **Why:** prebuilt tarball is the fastest path on tiny VPS but requires CI/release setup on upstream `decolua/9router` — out of script's control. Hybrid adds branching complexity. Remote-build changes UX from `curl | sudo bash` to "run from your laptop" which user explicitly didn't pick.
- **Cost:** install time stays in 5–8 min range on 1 GB. Acceptable.
- **Revisit if:** upstream starts publishing releases, or 512 MB tier becomes a target.

### D2. Spec floor = 1 GB (rejected: 512 MB, 2 GB)
- **Chosen:** optimize hard for 1 GB, gracefully tier down to tiny (<1 GB) and up to medium+ (≥2 GB).
- **Why:** matches the most common cheap-VPS tier, keeps on-VPS build viable. 512 MB would force prebuilt tarball (rejected in D1). 2 GB makes most optimizations vanity work.

### D3. gum interactive menu (rejected: pure flags, hybrid)
- **Chosen:** gum menu by default, subcommands directly callable, no flag mode.
- **Why:** matches existing `fsetup`/`fgit` pattern in this repo; user explicitly picked this. Adds gum dependency but it's already the repo convention.
- **Cost:** loses Ansible/CI ergonomics. Acceptable per scope.

### D4. Doctor with confirmation before fixes (rejected: silent auto-fix, read-only)
- **Chosen:** doctor diagnoses, lists fixes with severity, prompts before applying.
- **Why:** silent auto-fix surprises users (someone re-runs the script and finds journal config or systemd unit silently changed). Read-only loses the "self-improve" goal. Confirmed-fix is the safe middle.

### D5. zram instead of bigger disk swap on tiny/small tiers
- **Chosen:** enable `zram-config` (or `systemd-zram-generator`) at 50% of RAM, priority 100, with disk swap as overflow.
- **Why:** disk swap on cheap VPS has terrible random I/O latency. zram trades a small CPU cost for ~3× effective swap throughput. Worth it on every box <2 GB.

### D6. Auto-rollback on update, manual rollback subcommand
- **Chosen:** keep aside `/opt/9router-previous/` before deploy; auto-restore if build or service-start fails. Separate `rollback` subcommand for "service started but app is broken" cases.
- **Why:** current script has no rollback at all. Without it, a bad upstream commit can take the service down with no easy recovery. Cost is one extra rsync + one disk slot (~250 MB).

## Acceptance Criteria
- [ ] Running `bash setup_9router.sh` on a fresh Ubuntu 24.04, 1 GB / 1 vCPU / 20 GB VPS shows the banner, detects spec, classifies as `small`, and presents a gum menu.
- [ ] Selecting "Install" with a domain succeeds end-to-end in < 8 min and yields a working `https://<domain>` response.
- [ ] Selecting "Install" without a domain succeeds and yields a working `http://<ip>:<port>` response.
- [ ] On a 512 MB tier (downsize for testing), install either succeeds with zram active, or fails fast with a clear "RAM insufficient, need ≥1 GB" message — never gets stuck OOM-killing.
- [ ] Re-running the script and selecting "Update" pulls a new commit, redeploys, and shows old vs new commit hash.
- [ ] Forcing a build failure (e.g., break upstream temporarily) on update triggers auto-rollback; service stays on the previous commit.
- [ ] `doctor` on a healthy install reports all checks `OK`.
- [ ] `doctor` after manually changing a sysctl value reports drift with a one-line fix command and prompts before reapplying.
- [ ] `doctor --json` emits valid JSON consumable by `jq`.
- [ ] After install on a 1 GB VPS: idle RSS of `9router.service` ≤ 250 MB; disk used by 9router + node + caddy ≤ 600 MB.
- [ ] `uninstall` requires typing the domain (or "9router") to confirm and successfully removes service, runtime, env, Caddy config, and UFW rules — but **never** the data directory.
- [ ] All subcommands re-runnable without error.

## Dependencies / Assumptions
- Ubuntu 22.04 / 24.04 with `bash`, `curl`, `sudo`. Debian 11/12 best-effort.
- Internet egress to: nodesource.com, deb.cloudsmith.io (Caddy), npmjs.com, github.com, deb.debian.org / archive.ubuntu.com.
- Upstream `decolua/9router` keeps Next.js standalone build output at `.next/standalone/server.js`.
- DNS for the user's domain points to the VPS IP before install (else HTTPS issuance is skipped with a warning, current behavior).
- User has root or sudo. Script runs as root (current behavior).
- gum is installable via apt repo `https://repo.charm.sh/apt/` or via single-binary fallback.

## Open Questions
- **OQ1:** Should `doctor` poll the running 9router HTTP endpoint (e.g., a `/health` route) to check liveness, or is `systemctl is-active` enough? Depends on whether upstream exposes a health endpoint.
- **OQ2:** When new upstream commit changes the build command, do we want a `tune --upgrade-script` self-update from this dotfiles repo, or do we expect the user to re-`curl` the latest? (Likely the latter — keeps things simple.)
- **OQ3:** Should `tune` subcommand let the user manually override the detected tier (e.g., force-downgrade a 2 GB VPS to small-tier limits to leave room for other services)? Useful but adds config surface.
- **OQ4:** Where to keep the `/opt/9router-previous/` snapshot — kept indefinitely (~250 MB always-occupied) or pruned after N days? Disk-tight VPS prefers pruning.

## Deferred Ideas
- **DI1:** Prebuilt-tarball deployment (`curl https://github.com/decolua/9router/releases/.../9router-vX.tar.gz`). Massive low-spec win. Blocked on upstream CI.
- **DI2:** Flag-driven non-interactive mode for Ansible/CI users.
- **DI3:** `--json` output on every subcommand for monitoring integration.
- **DI4:** Docker-image deploy variant for users on hosts with Docker already installed.
- **DI5:** Backup/restore of `/var/lib/9router` data directory.
- **DI6:** Multi-domain Caddy config (host multiple 9router instances on one VPS).
- **DI7:** Prometheus node_exporter + 9router metrics endpoint integration.
- **DI8:** IPv6-specific sysctl tuning.

## Ambiguity Report
- **Goal clarity:** high — user gave four concrete aims (interactive, banner, detect, optimize+self-check) and confirmed all four strategic forks.
- **Scope clarity:** high — Out-of-Scope list is explicit; Deferred Ideas list captures everything punted.
- **Constraints clarity:** medium — bilingual message style is preserved by convention but not formalized; OQ2 (script self-update) is unresolved.
- **Acceptance clarity:** high — concrete byte/time/RSS thresholds and failure-mode tests listed.

## Next Handoff
Run `/plan` to break this into implementation phases (suggested split: Phase A = refactor into subcommands + menu + tier detection; Phase B = zram + tiered sysctl + MemoryMax + journald cap + unattended-upgrades; Phase C = doctor with prompted fixes; Phase D = update auto-rollback + uninstall + status).
