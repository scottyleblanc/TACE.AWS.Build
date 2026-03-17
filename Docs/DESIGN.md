# TACE.AWS.Build — Design Decisions

Architectural decisions made during development. Each entry records the decision,
the rationale, and the alternatives considered.

---

## D-001 — AWS Launch Templates over local JSON template files

**Date:** 2026-03-16
**Status:** Accepted

**Decision:**
Instance launch configuration (AMI, instance type, security groups, IAM profile, etc.)
is stored in AWS Launch Templates (native AWS feature) rather than local JSON files
in this module's `config/` directory.

**Rationale:**
- Launch Templates are versioned natively in AWS — full change history without git
- Visible and launchable from the AWS Console as a fallback, without PowerShell
- No dependency on local config for instance spec — spec is authoritative in AWS
- Keeps PowerShell module code focused on orchestration, not instance spec management
- Enables future Auto Scaling Group integration if needed
- Cost: zero — Launch Templates are free in AWS

The module stores only the Launch Template **ID reference** in `tace.aws.build.config.json`.
All instance spec is managed in the Launch Template via the AWS Console or CLI.

**Alternatives considered:**
- Local JSON template files (e.g. `tace.aws.build.linux.json`) — rejected because spec
  would be split across two systems (git + AWS), and the AWS Console would not reflect
  the true config.

**Future direction:**
`New-TaceLaunchTemplate` (planned, v0.2.0) — generate a new AWS Launch Template from a
local PowerShell profile definition. This enables code-driven Launch Template creation
and a path toward full infrastructure-as-code without leaving the PowerShell toolchain.

---

## D-002 — TACE.{Family}.{Product} naming convention

**Date:** 2026-03-16
**Status:** Accepted

**Decision:**
All published TACE PowerShell modules follow the pattern `TACE.{Family}.{Product}`.

| Family | Examples |
|---|---|
| `AWS` | `TACE.AWS.Run`, `TACE.AWS.Build` |
| `Oracle` | `TACE.Oracle.Admin`, `TACE.Oracle.Backup`, `TACE.Oracle.Wallet` |

**Rationale:**
- Aligns with Microsoft (`Az.Compute`) and AWS (`AWS.Tools.EC2`) PSGallery conventions
- Adds a discoverable product family grouping — all AWS modules are visually grouped
- PowerShell Gallery supports dot-separated names natively
- Enables future monorepo reorganisation without renaming modules

**Previous convention:** `TACE.{Product}` (e.g. `TACE.OracleBackup`) — retired.

---

## D-003 — Module split: TACE.AWS.Run and TACE.AWS.Build

**Date:** 2026-03-16
**Status:** Accepted

**Decision:**
The original `TACE.AWS` module is split into two separate modules with distinct
responsibilities:

| Module | Responsibility |
|---|---|
| `TACE.AWS.Run` | Operational control — start, stop, connect, status |
| `TACE.AWS.Build` | Infrastructure lifecycle — build instances, manage EIPs |

**Rationale:**
- Operational and lifecycle functions have different risk profiles — teardown is
  irreversible, operational functions are not. Separating them makes the blast radius
  of each module clear.
- Different release cadences — Run is stable; Build will evolve more quickly as
  infrastructure patterns develop.
- Follows the principle of least privilege at the module level — a user who only
  needs to start/stop instances does not need the build/teardown functions imported.
- Cleaner PSGallery packages — consumers can install only what they need.

**Repo structure:** Separate git repos (one per module), consistent with all other
TACE modules. Future option: consolidate into a `TACE.AWS` monorepo using `git subtree`.

---

## D-004 — Teardown confirmation: SupportsShouldProcess + typed confirmation

**Date:** 2026-03-16
**Status:** Accepted

**Decision:**
Destructive functions (`Remove-TaceInstance`, `Remove-TaceElasticIp`) require two
independent confirmation gates before executing any AWS API call:

1. `SupportsShouldProcess` with `ConfirmImpact = 'High'` — enables `-WhatIf` dry-run
2. Interactive typed confirmation — caller must type the exact instance name or IP address

**Rationale:**
- Infrastructure teardown is irreversible — terminated instances and released EIPs cannot
  be recovered. The cost of an accidental teardown is high.
- `-WhatIf` alone is insufficient — it is easily bypassed by omission.
- Typed confirmation is a deliberate act that cannot happen accidentally via tab-completion
  or copy-paste of a previous command.
- Development environment context (lower stakes) acknowledged, but the guard rails
  establish correct habits for future production use.

**Note:** Both gates can be bypassed in automated testing by mocking `Read-Host` and
using `-Confirm:$false`. This is intentional — test automation should not be blocked
by interactive prompts.
