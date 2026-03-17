# TACE.AWS.Build — Session Handoff

This document provides context for resuming work on the TACE.AWS.Build module
in a new session. Read this before starting any new work.

For the broader infrastructure picture (resource IDs, VPC, instances, access method,
session checklists) see `dev/TACE/repos/TACE.AWS.Run/Docs/HANDOFF.md`.

---

## Current State

**Version:** v0.1.0 — released 2026-03-17
**GitHub:** git@github.com:scottyleblanc/TACE.AWS.Build.git (private)
**Local path:** `dev/TACE/repos/TACE.AWS.Build/`
**PS profile:** Imported automatically — no manual import needed

Module is fully scaffolded and tested (33 tests, 0 failures). All three public
functions are implemented. The module is ready to use for teardown operations.

**New instance launches (`New-TaceInstance`) require AWS Launch Template IDs to
be configured before use** — see Configuration section below.

---

## What's Implemented

| Function | Status | Notes |
|---|---|---|
| `New-TaceInstance` | Implemented | Requires Launch Template IDs in config |
| `Remove-TaceInstance` | Implemented | Ready to use |
| `Remove-TaceElasticIp` | Implemented | Ready to use |
| `Assert-AwsCliAvailable` | Implemented (private) | Validates AWS CLI v2 |
| `Get-TaceLaunchTemplate` | Implemented (private) | Resolves profile name to LT ID |

---

## Configuration

Module config: `config/tace.aws.build.config.json`

```json
{
    "DefaultRegion": "ca-central-1",
    "DefaultProfile": "tace-aws-admin",
    "RunModuleConfigPath": "..\\TACE.AWS.Run\\config\\tace-aws.config.json",
    "LaunchTemplates": {
        "tace-linux": {
            "TemplateId": "lt-PLACEHOLDER",
            ...
        },
        "tace-windows": {
            "TemplateId": "lt-PLACEHOLDER",
            ...
        }
    }
}
```

`Remove-TaceInstance` and `Remove-TaceElasticIp` do not use Launch Templates
and work immediately with no config changes.

`New-TaceInstance` requires real Launch Template IDs. Two options:

1. **Create Launch Templates in AWS Console** — fill in the `TemplateId` values
   (format: `lt-xxxxxxxxxxxxxxxxx`). See `Docs/PREREQUISITES.md`.
2. **Defer** — planned v0.2.0 refactor will support launching from local JSON
   profile definitions without requiring AWS Launch Templates.

---

## Quick Reference

```powershell
# Dry-run teardown — always do this first
Remove-TaceInstance  -InstanceId i-0abc123 -InstanceName tace-linux-02 -WhatIf
Remove-TaceElasticIp -AllocationId eipalloc-0abc123 -PublicIp 15.157.x.x -WhatIf

# Actual teardown — typed confirmation required at each step
Remove-TaceInstance  -InstanceId i-0abc123 -InstanceName tace-linux-02
Remove-TaceElasticIp -AllocationId eipalloc-0abc123 -PublicIp 15.157.x.x

# Launch a new instance (requires Launch Template IDs in config)
New-TaceInstance -ProfileName tace-linux -Wait
```

---

## Teardown Order

Always terminate the instance before releasing the EIP:

1. `Remove-TaceInstance` — terminates the instance
2. `Remove-TaceElasticIp` — releases the EIP

---

## Next Session — v0.2.0 Planned Work

See `Docs/TODO.md` v0.2.0 section for the full list.

- `New-TaceLaunchTemplate` — generate an AWS Launch Template from a local profile definition
- `Get-TaceInstance` — list all instances with profile, name, state, EIP
- `Update-TaceRunConfig` — explicit function to sync new instance details to TACE.AWS.Run config

---

## Key Documents

| Document | Location |
|---|---|
| README | `dev/TACE/repos/TACE.AWS.Build/Docs/README.md` |
| TODO | `dev/TACE/repos/TACE.AWS.Build/Docs/TODO.md` |
| CHANGELOG | `dev/TACE/repos/TACE.AWS.Build/Docs/CHANGELOG.md` |
| SECURITY | `dev/TACE/repos/TACE.AWS.Build/Docs/SECURITY.md` |
| PREREQUISITES | `dev/TACE/repos/TACE.AWS.Build/Docs/PREREQUISITES.md` |
| DESIGN | `dev/TACE/repos/TACE.AWS.Build/Docs/DESIGN.md` |
| Infrastructure handoff | `dev/TACE/repos/TACE.AWS.Run/Docs/HANDOFF.md` |
| This document | `dev/TACE/repos/TACE.AWS.Build/Docs/HANDOFF.md` |
